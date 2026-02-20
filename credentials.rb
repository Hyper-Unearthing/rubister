require 'json'
require 'time'
require 'fileutils'
require 'llm_gateway'
require_relative 'lib/openai_oauth'

class Credentials
  AUTH_FILE_PATH = File.join(__dir__, 'auth.json')

  # Returns [access_token, refresh_token, expires_at, provider]
  def self.load(provider = nil, auth_string = nil)
    new.load(provider, auth_string)
  end

  def load(provider = nil, auth_string = nil)
    if auth_string
      tokens = parse_auth_string(auth_string)
      tokens << (provider || 'anthropic')
      tokens
    elsif File.exist?(AUTH_FILE_PATH)
      load_from_auth_file(provider)
    else
      if provider == 'openai'
        run_openai_oauth_flow
      else
        run_anthropic_oauth_flow
      end
    end
  end

  private

  def parse_auth_string(auth_string)
    params = {}

    auth_string.split('&').each do |pair|
      key, value = pair.split('=', 2)
      value = value.gsub(/^["']|["']$/, '') if value
      params[key] = value
    end

    access = params['access']
    refresh = params['refresh']
    expires = params['expires'] ? Time.at(params['expires'].to_i) : nil

    unless access
      puts "Error: auth string must contain 'access' parameter"
      exit 1
    end

    [access, refresh, expires]
  end

  def load_from_auth_file(provider = nil)
    auth_data = JSON.parse(File.read(AUTH_FILE_PATH))

    if provider == 'openai'
      if auth_data['openai']
        load_openai_section(auth_data)
      else
        run_openai_oauth_flow
      end
    elsif provider == 'anthropic'
      if auth_data['anthropic']
        load_anthropic_section(auth_data)
      else
        run_anthropic_oauth_flow
      end
    elsif provider.nil?
      # No provider specified — use whatever is in the file, prefer anthropic
      if auth_data['anthropic']
        load_anthropic_section(auth_data)
      elsif auth_data['openai']
        load_openai_section(auth_data)
      else
        run_anthropic_oauth_flow
      end
    else
      puts "Error: Unknown provider '#{provider}'"
      exit 1
    end
  rescue JSON::ParserError => e
    puts "Error: Could not parse auth file: #{e.message}"
    exit 1
  rescue Errno::ENOENT => e
    puts "Error: Could not read auth file: #{e.message}"
    exit 1
  end

  def load_anthropic_section(auth_data)
    data = auth_data['anthropic']
    [data['access'], data['refresh'], data['expires'] ? Time.at(data['expires']) : nil, 'anthropic']
  end

  def load_openai_section(auth_data)
    data = auth_data['openai']
    [data['access'], data['refresh'], data['expires'] ? Time.at(data['expires']) : nil, 'openai', data['account_id']]
  end

  def run_anthropic_oauth_flow
    flow = LlmGateway::Clients::ClaudeCode::OAuthFlow.new

    result = flow.start
    puts "Open this URL to authorize:"
    puts result[:authorization_url]
    puts
    print "Paste the code (format: code#state): "

    tty = File.open('/dev/tty', 'r')
    auth_code = tty.gets&.strip
    tty.close

    if auth_code.nil? || auth_code.empty?
      puts "Error: No authorization code provided"
      exit 1
    end

    tokens = flow.exchange_code(auth_code, result[:code_verifier])
    save_auth_file('anthropic', tokens)

    puts "Authenticated successfully!"
    puts

    [tokens[:access_token], tokens[:refresh_token], tokens[:expires_at], 'anthropic']
  end

  def run_openai_oauth_flow
    tokens = OpenAiOAuth.login
    save_auth_file('openai', tokens)

    puts "Authenticated successfully!"
    puts

    [tokens[:access_token], tokens[:refresh_token], tokens[:expires_at], 'openai', tokens[:account_id]]
  end

  def save_auth_file(provider, tokens)
    auth_data = if File.exist?(AUTH_FILE_PATH)
      JSON.parse(File.read(AUTH_FILE_PATH))
    else
      {}
    end

    if provider == 'openai'
      auth_data['openai'] = {
        'access' => tokens[:access_token],
        'refresh' => tokens[:refresh_token],
        'expires' => tokens[:expires_at]&.to_i,
        'account_id' => tokens[:account_id]
      }
    else
      auth_data['anthropic'] = {
        'access' => tokens[:access_token],
        'refresh' => tokens[:refresh_token],
        'expires' => tokens[:expires_at]&.to_i
      }
    end

    FileUtils.mkdir_p(File.dirname(AUTH_FILE_PATH))
    File.write(AUTH_FILE_PATH, JSON.pretty_generate(auth_data))
  end
end
