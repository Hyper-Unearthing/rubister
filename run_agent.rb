#!/usr/bin/env ruby

require 'optparse'
require 'securerandom'
require 'llm_gateway'
require_relative 'agent'
require_relative 'prompt'
require_relative 'credentials'
require_relative 'lib/openai_oauth'

# Enable immediate output flushing for real-time streaming
$stdout.sync = true

# Simple runner that takes auth and message arguments
class AgentRunner
  def initialize
    @options = {
      model: nil,
      provider: nil,
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

      opts.on('-p PROVIDER', '--provider PROVIDER', 'Provider: anthropic (default) or openai') do |p|
        @options[:provider] = p
      end

      opts.on('--model MODEL', 'Model name') do |model|
        @options[:model] = model
      end

      opts.on('-h', '--help', 'Prints this help') do
        puts opts
        exit
      end
    end.parse!
  end

  def run
    parse_args
    credentials = Credentials.load(@options[:provider], @options[:auth])

    # Credentials returns [access, refresh, expires, provider, ...extra]
    api_key, refresh_token, expires_at, provider = credentials[0..3]

    client = if provider == 'openai'
      account_id = credentials[4]
      model = @options[:model] || 'gpt-5.1-codex-mini'
      LlmGateway.build_provider(
        provider: 'openai_oauth_responses',
        model_key: model,
        access_token: api_key,
        refresh_token: refresh_token,
        expires_at: expires_at,
        account_id: account_id
      )
    else
      model = @options[:model] || 'claude_code/claude-sonnet-4-5'
      LlmGateway.build_provider(
        provider: 'anthropic_oauth_messages',
        model_key: model,
        access_token: api_key,
        refresh_token: refresh_token,
        expires_at: expires_at
      )
    end
    @agent = Agent.new(Prompt, model, client)

    if @options[:message]
      # Single message mode
      @agent.run(@options[:message]) do |message|
        puts message
      end
      write_transcript
    else
      # Interactive mode
      run_interactive
    end
  end

  def transcript_path
    unless @transcript_file
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      session_id = SecureRandom.uuid
      dir = File.join(File.dirname(__FILE__), 'sessions')
      Dir.mkdir(dir) unless Dir.exist?(dir)
      @transcript_file = File.join(dir, "#{timestamp}_#{session_id}.json")
    end
    @transcript_file
  end

  def write_transcript
    transcript_data = {
      model: @agent.model,
      messages: @agent.transcript
    }
    File.write(transcript_path, JSON.pretty_generate(transcript_data))
  end

  def run_interactive
    rl = (require 'readline' rescue false)

    # Point Readline at /dev/tty so bracketed paste works even when stdout is piped
    if rl
      tty_in  = File.open('/dev/tty', 'r')
      tty_out = File.open('/dev/tty', 'w')
      Readline.input  = tty_in
      Readline.output = tty_out
    end

    puts "Interactive mode (type 'exit' or 'quit' to end, Ctrl+D to send EOF)"
    puts '---'

    loop do
      $stdout.flush

      input = if rl
        Readline.readline('> ', true)
      else
        print '> '
        t = File.open('/dev/tty', 'r')
        line = t.gets
        t.close
        line&.chomp
      end

      # Handle EOF (Ctrl+D) or exit commands
      break if input.nil? || input.strip.match?(/^(exit|quit)$/i)

      message = input.strip
      next if message.empty?

      @agent.run(message) do |output|
        puts output
      end
      write_transcript

      # Print newline after agent output completes
      puts
    end

    puts 'Goodbye!'
  ensure
    if rl
      tty_in&.close
      tty_out&.close
    end
  end


end

# Run if executed directly (expand paths for bundler compatibility)
if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
  runner = AgentRunner.new
  runner.run
end
