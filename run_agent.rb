#!/usr/bin/env ruby

require 'optparse'
require 'securerandom'
require 'llm_gateway'
require_relative 'agent'
require_relative 'prompt'
require_relative 'credentials'

# Enable immediate output flushing for real-time streaming
$stdout.sync = true

# Simple runner that takes auth and message arguments
class AgentRunner
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

      opts.on('-h', '--help', 'Prints this help') do
        puts opts
        exit
      end
    end.parse!
  end

  def run
    parse_args
    api_key, refresh_token, expires_at = Credentials.load(@options[:auth])
    @agent = Agent.new(Prompt, @options[:model], api_key, refresh_token: refresh_token, expires_at: expires_at)

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
    File.write(transcript_path, JSON.pretty_generate(@agent.transcript))
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
