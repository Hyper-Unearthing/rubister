#!/usr/bin/env ruby

require 'optparse'
require 'json'
require 'fileutils'
require 'llm_gateway'
require_relative 'lib/agent'
require_relative 'lib/coding_agent'
require_relative 'lib/logging'
require_relative 'modes/interactive'
require_relative 'modes/message'
require_relative 'lib/sessions/file_session_manager'
require_relative 'lib/agent_session'

$stdout.sync = true

class AgentRunner
  AUTH_FILE = File.expand_path(ENV.fetch('GRUV_AUTH_FILE', '~/.config/gruv/auth.json'))

  SUPPORTED_PROVIDERS = %w[
    anthropic_apikey_messages
    openai_apikey_completions
    openai_apikey_responses
    openai_oauth_codex
  ].freeze

  def initialize
    @options = {
      provider: 'anthropic_apikey_messages',
      model: nil,
      message: nil,
      session_file: nil
    }
  end

  def parse_args
    OptionParser.new do |opts|
      opts.banner = 'Usage: run_agent.rb [options]'

      opts.on('-p PROVIDER', '--provider PROVIDER', "Provider key (#{SUPPORTED_PROVIDERS.join(', ')})") do |provider|
        @options[:provider] = provider
      end

      opts.on('-m MODEL', '--model MODEL', 'Model name') do |model|
        @options[:model] = model
      end

      opts.on('--message MESSAGE', 'The prompt/message for the agent') do |message|
        @options[:message] = message
      end

      opts.on('-s FILE', '--session FILE', 'Load an existing session file') do |file|
        @options[:session_file] = file
      end

      opts.on('-h', '--help', 'Print help') do
        puts opts
        exit
      end
    end.parse!
  end

  def run
    parse_args
    client = build_client

    if @options[:message]
      MessageMode.new(client, @options[:session_file], @options[:message]).run
    else
      InteractiveRunner.new(client, @options[:session_file]).run
    end
  end

  private

  def build_client
    provider = @options[:provider]
    unless SUPPORTED_PROVIDERS.include?(provider)
      puts "Unsupported provider '#{provider}'. Supported: #{SUPPORTED_PROVIDERS.join(', ')}"
      exit 1
    end

    config = {
      'provider' => provider,
      'model_key' => resolve_model(provider)
    }

    case provider
    when 'openai_apikey_completions', 'openai_apikey_responses'
      api_key = ENV['OPENAI_API_KEY']
      unless api_key
        puts 'OPENAI_API_KEY is required for OpenAI API key providers'
        exit 1
      end
      config['api_key'] = api_key
    when 'anthropic_apikey_messages'
      if auth_credentials_available?('anthropic')
        config['api_key'] = oauth_access_token_for('anthropic')
      else
        api_key = ENV['ANTHROPIC_API_KEY']
        unless api_key
          puts "ANTHROPIC_API_KEY required or add anthropic credentials in #{AUTH_FILE}"
          exit 1
        end
        config['api_key'] = api_key
      end
    when 'openai_oauth_codex'
      creds = load_auth_credentials('openai')
      config['api_key'] = oauth_access_token_for('openai')
      config['account_id'] = creds['account_id'] if creds['account_id']
    end

    LlmGateway.build_provider(config)
  end

  def resolve_model(provider)
    return @options[:model] if @options[:model]

    case provider
    when 'anthropic_apikey_messages'
      'claude-sonnet-4-20250514'
    when 'openai_apikey_completions'
      'gpt-5.1'
    when 'openai_apikey_responses'
      'gpt-5.4'
    when 'openai_oauth_codex'
      'gpt-5.4'
    end
  end

  def auth_credentials_available?(provider)
    return false unless File.exist?(AUTH_FILE)

    auth = JSON.parse(File.read(AUTH_FILE))
    auth.key?(provider)
  rescue JSON::ParserError
    false
  end

  def load_auth_credentials(provider)
    unless File.exist?(AUTH_FILE)
      puts "Missing auth file at #{AUTH_FILE}. Run: ruby setup_provider.rb #{provider}"
      exit 1
    end

    auth = JSON.parse(File.read(AUTH_FILE))
    creds = auth[provider]
    unless creds
      puts "Missing #{provider} credentials in #{AUTH_FILE}. Run: ruby setup_provider.rb #{provider}"
      exit 1
    end

    creds
  rescue JSON::ParserError
    puts "Invalid JSON in #{AUTH_FILE}"
    exit 1
  end

  def persist_auth_credentials(provider, attributes)
    auth = File.exist?(AUTH_FILE) ? JSON.parse(File.read(AUTH_FILE)) : {}
    auth[provider] ||= {}
    auth[provider].merge!(attributes)

    FileUtils.mkdir_p(File.dirname(AUTH_FILE))
    File.write(AUTH_FILE, JSON.pretty_generate(auth) + "\n")
  end

  def oauth_access_token_for(provider)
    creds = load_auth_credentials(provider)

    case provider
    when 'anthropic'
      token = LlmGateway::Clients::Claude.new.get_oauth_access_token(
        access_token: creds['access_token'],
        refresh_token: creds['refresh_token'],
        expires_at: creds['expires_at']
      ) do |access_token, refresh_token, expires_at|
        persist_auth_credentials('anthropic', {
                                   'access_token' => access_token,
                                   'refresh_token' => refresh_token,
                                   'expires_at' => expires_at&.iso8601
                                 })
      end

      persist_auth_credentials('anthropic', { 'access_token' => token }) if token != creds['access_token']
      token
    when 'openai'
      token = LlmGateway::Clients::OpenAi.new.get_oauth_access_token(
        access_token: creds['access_token'],
        refresh_token: creds['refresh_token'],
        expires_at: creds['expires_at'],
        account_id: creds['account_id']
      ) do |access_token, refresh_token, expires_at|
        persist_auth_credentials('openai', {
                                   'access_token' => access_token,
                                   'refresh_token' => refresh_token,
                                   'expires_at' => expires_at&.iso8601
                                 })
      end

      persist_auth_credentials('openai', { 'access_token' => token }) if token != creds['access_token']
      token
    end
  end
end

AgentRunner.new.run if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
