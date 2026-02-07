#!/usr/bin/env ruby

# Setup bundler inline so it works with or without 'bundle exec'
require 'bundler/setup'
Bundler.require(:default)

require 'optparse'
require 'json'
require 'time'
require_relative 'claude_code_clone'

# Enable immediate output flushing for real-time streaming
$stdout.sync = true

# Simple runner that takes auth and message arguments
class AgentRunner
  AUTH_FILE_PATH = File.expand_path('~/.local/share/opencode/auth.json')

  def initialize
    @options = {
      model: 'claude_code/claude-sonnet-4-5',
      message: nil,
      auth: nil
    }
  end

  def parse_args
    OptionParser.new do |opts|
      opts.banner = 'Usage: run_agent.rb [options]'

      opts.on('-m MESSAGE', '--message MESSAGE', 'The prompt/message for the agent') do |m|
        @options[:message] = m
      end

      opts.on('--auth AUTH_STRING',
              'Auth string in format: type="oauth"&refresh="xxx"&access="yyy"&expires=123') do |a|
        @options[:auth] = a
      end

      opts.on('--model MODEL', 'Model to use (default: claude_code/claude-sonnet-4-5)') do |m|
        @options[:model] = m
      end

      opts.on('-h', '--help', 'Prints this help') do
        puts opts
        exit
      end
    end.parse!
  end

  def run
    parse_args
    api_key, refresh_token, expires_at = load_credentials
    @agent = Agent.new(Prompt, @options[:model], api_key, refresh_token: refresh_token, expires_at: expires_at)

    if @options[:message]
      # Single message mode
      @agent.run(@options[:message]) do |message|
        puts message
      end
    else
      # Interactive mode
      run_interactive
    end
  end

  def run_interactive
    # Open /dev/tty to read from terminal even when stdout is piped
    tty = File.open('/dev/tty', 'r+')

    puts "Interactive mode (type 'exit' or 'quit' to end, Ctrl+D to send EOF)"
    puts '---'

    loop do
      $stdout.flush

      input = tty.gets

      # Handle EOF (Ctrl+D) or exit commands
      break if input.nil? || input.strip.match?(/^(exit|quit)$/i)

      message = input.strip
      next if message.empty?

      @agent.run(message) do |output|
        puts output
      end

      # Print newline after agent output completes
      puts
    end

    puts 'Goodbye!'
  ensure
    tty.close if tty
  end

  private

  def load_credentials
    if @options[:auth]
      parse_auth_string(@options[:auth])
    else
      load_from_auth_file
    end
  end

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
    unless File.exist?(AUTH_FILE_PATH)
      puts "Error: Auth file not found at #{AUTH_FILE_PATH} and no --auth argument provided"
      exit 1
    end

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
end

# Run if executed directly (expand paths for bundler compatibility)
if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  runner = AgentRunner.new
  runner.run
end
