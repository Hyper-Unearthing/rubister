# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'llm_gateway'

module ProviderAuthHelper
  AUTH_FILE = File.expand_path(ENV.fetch('GRUV_AUTH_FILE', '~/.config/gruv/auth.json'))

  def auth_credentials_available?(provider)
    return false unless File.exist?(AUTH_FILE)

    auth = JSON.parse(File.read(AUTH_FILE))
    auth.key?(provider)
  rescue JSON::ParserError
    false
  end

  def load_auth_credentials(provider)
    raise "Missing auth file at #{AUTH_FILE}. Run: ruby setup_provider.rb #{provider}" unless File.exist?(AUTH_FILE)

    auth = JSON.parse(File.read(AUTH_FILE))
    creds = auth[provider]
    raise "Missing #{provider} credentials in #{AUTH_FILE}. Run: ruby setup_provider.rb #{provider}" unless creds

    creds
  rescue JSON::ParserError
    raise "Invalid JSON in #{AUTH_FILE}"
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
    else
      raise "Unsupported OAuth provider '#{provider}'"
    end
  end

  def apply_provider_auth!(provider_name, config)
    case provider_name
    when 'anthropic_apikey_messages'
      if auth_credentials_available?('anthropic')
        config['api_key'] = oauth_access_token_for('anthropic')
      else
        api_key = ENV['ANTHROPIC_API_KEY']
        raise "ANTHROPIC_API_KEY required or add anthropic credentials in #{AUTH_FILE}" unless api_key

        config['api_key'] = api_key
      end
    when 'openai_oauth_codex'
      creds = load_auth_credentials('openai')
      config['api_key'] = oauth_access_token_for('openai')
      config['account_id'] = creds['account_id'] if creds['account_id']
    when 'openai_apikey_completions', 'openai_apikey_responses'
      api_key = ENV['OPENAI_API_KEY']
      raise 'OPENAI_API_KEY is required for OpenAI API key providers' unless api_key

      config['api_key'] = api_key
    else
      raise "Unsupported provider '#{provider_name}'"
    end

    config
  end
end
