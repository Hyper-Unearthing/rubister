#!/usr/bin/env -S bundle exec ruby
# frozen_string_literal: true

# Unified setup wizard for gruv.
# Run multiple times safely — existing values are shown as defaults and
# OAuth tokens for the same provider are overwritten while other settings
# are preserved unless you explicitly change them.

require 'json'
require 'fileutils'
require 'uri'

# --instance-path <dir> lets gruvctl call setup.rb directly on the host,
# pointing at a bind-mounted instance directory — no docker exec needed.
instance_path_flag = ARGV.index('--instance-path')
INSTANCE_DIR =
  if instance_path_flag
    ARGV.delete_at(instance_path_flag)
    dir = ARGV.delete_at(instance_path_flag) || abort('  ✗ --instance-path requires a directory argument')
    abort "  ✗ directory does not exist: #{dir}" unless Dir.exist?(dir)
    dir
  else
    require_relative 'lib/instance_file_scope'
    InstanceFileScope.instance_dir
  end

CONFIG_PATH    = File.join(INSTANCE_DIR, 'config.json')
AUTH_PATH = File.expand_path(ENV.fetch('GRUV_AUTH_FILE', '~/.config/gruv/auth.json'))

ANTHROPIC_REGISTRY_KEY = 'anthropic'
OPENAI_REGISTRY_KEY    = 'openai'


# ─── TTY helpers ─────────────────────────────────────────────────────────────

def tty
  @tty ||= File.open('/dev/tty', 'r+')
end

def ask(label, default: nil, required: false, secret: false)
  loop do
    display = default ? "#{label} [#{secret ? '***' : default}]" : label
    tty.print("#{display}: ")

    value = tty.gets&.strip
    value = default if value == '' && !default.nil?

    return value if !required || (value && !value.empty?)

    tty.puts '  ✗ This value is required.'
  end
end

def ask_yn(label, default: true)
  suffix = default ? '[Y/n]' : '[y/N]'
  tty.print("#{label} #{suffix}: ")
  input = tty.gets&.strip&.downcase
  return default if input.nil? || input.empty?

  %w[y yes].include?(input)
end

def hr(char = '─', width: 60)
  tty.puts char * width
end

def section(title)
  tty.puts
  hr
  tty.puts "  #{title}"
  hr
end

# ─── JSON persistence ─────────────────────────────────────────────────────────

def load_json(path)
  return {} unless File.exist?(path)

  JSON.parse(File.read(path))
rescue JSON::ParserError
  {}
end

def save_json(path, data)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(data) + "\n")
end

# ─── Menu ─────────────────────────────────────────────────────────────────────

MENU_ITEMS = [
  { key: :anthropic,  label: 'Anthropic (Claude) — OAuth provider' },
  { key: :openai,     label: 'OpenAI (GPT/Codex) — OAuth provider' },
  { key: :telegram,   label: 'Telegram — bot token' },
  { key: :discord,    label: 'Discord — bot + OAuth app' },
  { key: :assemblyai, label: 'AssemblyAI — transcription API key' }
].freeze

def pick_section(config, providers)
  tty.puts
  tty.puts '╔══════════════════════════════════════════════╗'
  tty.puts '║            gruv — setup wizard               ║'
  tty.puts '╚══════════════════════════════════════════════╝'
  tty.puts
  tty.puts 'What would you like to set up?'
  tty.puts '  (Enter one number, or "exit")'
  tty.puts

  MENU_ITEMS.each_with_index do |item, i|
    status = configured_status(item[:key], config, providers)
    tty.puts "  #{i + 1}) #{item[:label]}  #{status}"
  end

  tty.puts
  tty.print 'Your choice: '
  input = tty.gets&.strip

  return :exit if input.nil?

  normalized = input.downcase
  return :exit if normalized == 'exit' || normalized == 'quit'

  return nil unless normalized =~ /^\d+$/

  idx = normalized.to_i - 1
  MENU_ITEMS[idx]&.fetch(:key)
end

def configured_status(key, config, providers)
  case key
  when :anthropic  then providers.key?(ANTHROPIC_REGISTRY_KEY) ? '✓ configured' : '○ not set'
  when :openai     then providers.key?(OPENAI_REGISTRY_KEY)    ? '✓ configured' : '○ not set'
  when :telegram   then config.dig('telegram', 'bot_token') || config['telegram_bot_token'] ? '✓ configured' : '○ not set'
  when :discord    then config.dig('discord', 'bot_token')  || config['discord_bot_token']  ? '✓ configured' : '○ not set'
  when :assemblyai then config['assemblyai_api_key'] ? '✓ configured' : '○ not set'
  end
end

# ─── Provider setup ───────────────────────────────────────────────────────────

def setup_anthropic(providers)
  section 'Anthropic OAuth setup'

  require 'llm_gateway'

  existing = providers[ANTHROPIC_REGISTRY_KEY] || {}

  run_oauth = if existing.key?('access_token')
    tty.puts
    tty.puts "  Existing tokens found (expires_at: #{existing['expires_at']})."
    ask_yn('Re-run OAuth to get fresh tokens?', default: true)
  else
    true
  end

  tokens = if run_oauth
    tty.puts
    tty.puts '  Starting Anthropic OAuth flow...'
    tty.puts

    flow   = LlmGateway::Clients::ClaudeCode::OAuthFlow.new
    result = flow.start

    tty.puts '  Open this URL to authorize:'
    tty.puts "  #{result[:authorization_url]}"
    tty.puts

    auth_code = ask('Paste the code (format: code#state)', required: true)
    flow.exchange_code(auth_code, result[:code_verifier])
  end

  entry = existing.dup

  if tokens
    entry.merge!(
      'access_token'  => tokens[:access_token],
      'refresh_token' => tokens[:refresh_token],
      'expires_at'    => tokens[:expires_at]&.to_i
    )
    entry['account_id'] = tokens[:account_id] if tokens[:account_id]
  end

  providers[ANTHROPIC_REGISTRY_KEY] = entry
  tty.puts
  tty.puts '  ✓ Anthropic saved'
end

def setup_openai(providers)
  section 'OpenAI OAuth setup'

  require 'llm_gateway'

  existing = providers[OPENAI_REGISTRY_KEY] || {}

  reasoning = 'high'

  run_oauth = if existing.key?('access_token')
    tty.puts
    tty.puts "  Existing tokens found (expires_at: #{existing['expires_at']})."
    ask_yn('Re-run OAuth to get fresh tokens?', default: true)
  else
    true
  end

  tokens = run_oauth ? LlmGateway::Clients::OpenAi::OAuthFlow.new.login : nil

  entry = existing.dup
  entry['reasoning'] = reasoning

  if tokens
    entry.merge!(
      'access_token'  => tokens[:access_token],
      'refresh_token' => tokens[:refresh_token],
      'expires_at'    => tokens[:expires_at]&.to_i,
      'account_id'    => tokens[:account_id]
    )
  end

  providers[OPENAI_REGISTRY_KEY] = entry
  tty.puts
  tty.puts "  ✓ OpenAI saved#{reasoning ? ", reasoning: #{reasoning}" : ''}"
end

# ─── Chat integration setup ───────────────────────────────────────────────────

def setup_telegram(config)
  section 'Telegram bot setup'

  existing      = config['telegram'] || {}
  current_token = existing['bot_token'] || config['telegram_bot_token']

  tty.puts
  tty.puts '  Create a bot via @BotFather on Telegram to get a token.'
  tty.puts

  token = ask('Bot token', default: current_token, required: true, secret: true)

  config['telegram'] = existing.merge('bot_token' => token)
  config.delete('telegram_bot_token') # remove legacy flat key if present

  tty.puts
  tty.puts '  ✓ Telegram bot token saved'
end

def setup_discord(config)
  section 'Discord bot & app setup'

  existing = config['discord'] || {}
  # Support legacy flat keys as fallback defaults
  def_bot_token     = existing['bot_token']    || config['discord_bot_token']
  def_client_id     = existing['client_id']    || config['discord_client_id']
  def_client_secret = existing['client_secret']|| config['discord_client_secret']
  def_redirect_uri  = existing['redirect_uri'] || config['discord_redirect_uri']
  def_scopes        = existing['oauth_scopes'] || config['discord_oauth_scopes'] || 'bot applications.commands'
  def_permissions   = existing['permissions']  || config['discord_permissions']  || '274877991936'

  tty.puts
  tty.puts '  Get your bot token and app credentials from https://discord.com/developers/applications'
  tty.puts

  bot_token     = ask('Bot token',            default: def_bot_token,     required: true, secret: true)
  client_id     = ask('Application client ID', default: def_client_id,    required: true)
  client_secret = ask('Client secret (optional)', default: def_client_secret, secret: true)
  redirect_uri  = ask('Redirect URI (optional)',  default: def_redirect_uri)
  oauth_scopes  = ask('OAuth scopes',  default: def_scopes,       required: true)
  permissions   = ask('Permissions integer', default: def_permissions, required: true)

  install_url = build_discord_install_url(
    client_id: client_id,
    scopes: oauth_scopes,
    permissions: permissions,
    redirect_uri: redirect_uri
  )

  tty.puts
  tty.puts '  Open this Discord installation URL to add the bot to your server:'
  tty.puts "  #{install_url}"
  tty.puts

  return_url = ask('Paste resulting browser URL after installation (optional)')

  updates = {
    'bot_token'    => bot_token,
    'client_id'    => client_id,
    'oauth_scopes' => oauth_scopes,
    'permissions'  => permissions,
    'install_url'  => install_url
  }
  updates['client_secret'] = client_secret if client_secret && !client_secret.empty?
  updates['redirect_uri']  = redirect_uri  if redirect_uri  && !redirect_uri.empty?

  if return_url && !return_url.empty?
    updates.merge!(parse_discord_return_url(return_url))
  end

  config['discord'] = existing.merge(updates)

  # Remove legacy flat keys
  %w[discord_bot_token discord_client_id discord_client_secret discord_redirect_uri
     discord_oauth_scopes discord_permissions discord_install_url].each { |k| config.delete(k) }

  tty.puts
  tty.puts '  ✓ Discord configuration saved'
end

def build_discord_install_url(client_id:, scopes:, permissions:, redirect_uri:)
  query = {
    'client_id'   => client_id,
    'scope'       => scopes,
    'permissions' => permissions
  }

  if redirect_uri && !redirect_uri.empty?
    query['redirect_uri']  = redirect_uri
    query['response_type'] = 'code'
  end

  "https://discord.com/oauth2/authorize?#{URI.encode_www_form(query)}"
end

def parse_discord_return_url(url)
  uri    = URI(url)
  params = URI.decode_www_form(uri.query || '').to_h

  {
    'install_return_url'        => url,
    'install_code'              => params['code'],
    'install_guild_id'          => params['guild_id'],
    'install_permissions'       => params['permissions'],
    'install_scope'             => params['scope'],
    'install_error'             => params['error'],
    'install_error_description' => params['error_description']
  }
rescue URI::InvalidURIError
  tty.puts '  ✗ Could not parse return URL — skipping.'
  {}
end

def setup_assemblyai(config)
  section 'AssemblyAI API key setup'

  existing_key = config['assemblyai_api_key']

  tty.puts
  tty.puts '  Get your API key from https://www.assemblyai.com/'
  tty.puts

  api_key = ask('API key', default: existing_key, required: true, secret: true)

  config['assemblyai_api_key'] = api_key

  tty.puts
  tty.puts '  ✓ AssemblyAI API key saved'
end

# ─── Main ─────────────────────────────────────────────────────────────────────

config    = load_json(CONFIG_PATH)
providers = load_json(AUTH_PATH)

loop do
  section_key = pick_section(config, providers)

  if section_key == :exit
    tty.puts 'Exiting setup wizard.'
    break
  end

  unless section_key
    tty.puts 'Invalid choice — returning to menu.'
    next
  end

  case section_key
  when :anthropic  then setup_anthropic(providers)
  when :openai     then setup_openai(providers)
  when :telegram   then setup_telegram(config)
  when :discord    then setup_discord(config)
  when :assemblyai then setup_assemblyai(config)
  end

  save_json(CONFIG_PATH,    config)
  save_json(AUTH_PATH, providers)

  tty.puts
  hr('═')
  tty.puts '  Setup complete! Returning to main menu.'
  tty.puts "  Config:    #{CONFIG_PATH}"
  tty.puts "  Auth:      #{AUTH_PATH}"
  hr('═')
  tty.puts
end

tty.close if @tty && !@tty.closed?
