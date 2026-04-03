#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'llm_gateway'

AUTH_FILE = File.expand_path(ENV.fetch('GRUV_AUTH_FILE', '~/.config/gruv/auth.json'))

SUPPORTED_PROVIDERS = {
  'anthropic' => {
    auth_key: 'anthropic',
    default_model: 'claude-sonnet-4-5'
  },
  'openai' => {
    auth_key: 'openai',
    default_model: 'gpt-5.1-codex-mini'
  }
}.freeze

def run_oauth_flow(provider)
  case provider
  when 'anthropic'
    flow = LlmGateway::Clients::ClaudeCode::OAuthFlow.new
    result = flow.start
    puts 'Open this URL to authorize:'
    puts result[:authorization_url]
    puts
    print 'Paste the code (format: code#state): '

    tty = File.open('/dev/tty', 'r')
    auth_code = tty.gets&.strip
    tty.close

    if auth_code.nil? || auth_code.empty?
      puts 'Error: No authorization code provided'
      exit 1
    end

    flow.exchange_code(auth_code, result[:code_verifier])
  when 'openai'
    LlmGateway::Clients::OpenAiCodex::OAuthFlow.new.login
  end
end

def load_auth
  return {} unless File.exist?(AUTH_FILE)

  JSON.parse(File.read(AUTH_FILE))
rescue JSON::ParserError
  {}
end

def save_provider(provider_key, tokens)
  auth = load_auth

  entry = {
    'access_token' => tokens[:access_token],
    'refresh_token' => tokens[:refresh_token],
    'expires_at' => tokens[:expires_at]&.iso8601
  }
  entry['account_id'] = tokens[:account_id] if tokens[:account_id]

  auth[provider_key] = entry

  FileUtils.mkdir_p(File.dirname(AUTH_FILE))
  File.write(AUTH_FILE, JSON.pretty_generate(auth) + "\n")
end

provider = ARGV[0]

unless SUPPORTED_PROVIDERS.key?(provider)
  puts 'Usage: ruby setup_provider.rb <provider>'
  puts "Supported providers: #{SUPPORTED_PROVIDERS.keys.join(', ')}"
  exit 1
end

config = SUPPORTED_PROVIDERS[provider]
tokens = run_oauth_flow(provider)
save_provider(config[:auth_key], tokens)

puts "Provider '#{config[:auth_key]}' saved to #{AUTH_FILE}"
puts "Default model for #{provider}: #{config[:default_model]}"
