require 'json'
require 'time'
require 'fileutils'
require 'llm_gateway'

class Credentials
  AUTH_FILE_PATH = File.join(__dir__, 'auth.json')

  def self.load(auth_string = nil)
    new.load(auth_string)
  end

  def load(auth_string = nil)
    if auth_string
      parse_auth_string(auth_string)
    elsif File.exist?(AUTH_FILE_PATH)
      load_from_auth_file
    else
      run_oauth_flow
    end
  end

  private

  def parse_auth_string(auth_string)
    # Parse string like: type="oauth"&refresh="wer"&access="abc"&expires=123
    params = {}

    auth_string.split('&').each do |pair|
      key, value = pair.split('=', 2)
      # Remove quotes if present
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

  def load_from_auth_file
    auth_data = JSON.parse(File.read(AUTH_FILE_PATH))
    anthropic_data = auth_data['anthropic']

    unless anthropic_data
      puts "Error: No 'anthropic' section found in auth file"
      exit 1
    end

    access = anthropic_data['access']
    refresh = anthropic_data['refresh']
    expires = anthropic_data['expires'] ? Time.at(anthropic_data['expires']) : nil

    [access, refresh, expires]
  rescue JSON::ParserError => e
    puts "Error: Could not parse auth file: #{e.message}"
    exit 1
  rescue Errno::ENOENT => e
    puts "Error: Could not read auth file: #{e.message}"
    exit 1
  end

  def run_oauth_flow
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
    save_auth_file(tokens)

    puts "Authenticated successfully!"
    puts

    [tokens[:access_token], tokens[:refresh_token], tokens[:expires_at]]
  end

  def save_auth_file(tokens)
    auth_data = {
      'anthropic' => {
        'access' => tokens[:access_token],
        'refresh' => tokens[:refresh_token],
        'expires' => tokens[:expires_at]&.to_i
      }
    }

    FileUtils.mkdir_p(File.dirname(AUTH_FILE_PATH))
    File.write(AUTH_FILE_PATH, JSON.pretty_generate(auth_data))
  end
end
