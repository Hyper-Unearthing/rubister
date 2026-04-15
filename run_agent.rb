#!/usr/bin/env ruby

require 'optparse'
require 'llm_gateway'
require_relative 'lib/agent'
require_relative 'lib/coding_agent'
require_relative 'lib/logging'
require_relative 'modes/interactive'
require_relative 'modes/message'
require_relative 'lib/runtime_config'
require_relative 'lib/provider_auth_helper'
require_relative 'modes/daemon'
# Enable immediate output flushing for real-time streaming
$stdout.sync = true

# Simple runner that takes auth and message arguments
class AgentRunner
  include ProviderAuthHelper

  SUPPORTED_PROVIDERS = %w[
    anthropic_apikey_messages
    openai_apikey_completions
    openai_apikey_responses
    openai_oauth_codex
  ].freeze
  INBOX_DB_PATH = InstanceFileScope.path('gruv.sqlite3')

  def initialize
    @options = {
      provider: nil,
      model: nil,
      message: nil,
      session_file: nil,
      daemon: false,
      poll_interval: 1
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

      opts.on('-d', '--daemon', 'Run in daemon mode (process inbox messages)') do
        @options[:daemon] = true
      end

      opts.on('--poll-interval SECONDS', Integer, 'Polling interval for daemon mode (default: 1)') do |interval|
        @options[:poll_interval] = interval
      end

      opts.on('-h', '--help', 'Prints this help') do
        puts opts
        exit
      end
    end.parse!
  end

  def run
    parse_args
    client = build_client

    if @options[:message]
      MessageMode.new(client, @options[:session_file]).run(@options[:message])
    elsif @options[:daemon]
      daemon = DaemonMode.new(client, INBOX_DB_PATH, poll_interval: @options[:poll_interval])
      daemon.start
    else
      InteractiveRunner.new(client, @options[:session_file]).run
    end
  end

  private

  def build_client
    provider = @options[:provider]
    unless provider
      puts 'Missing required option: --provider'
      exit 1
    end

    unless SUPPORTED_PROVIDERS.include?(provider)
      puts "Unsupported provider '#{provider}'. Supported: #{SUPPORTED_PROVIDERS.join(', ')}"
      exit 1
    end

    unless @options[:model]
      puts 'Missing required option: --model'
      exit 1
    end

    agent_config = {
      'provider' => provider,
      'model_key' => resolve_model(provider)
    }

    RuntimeConfig.set(provider_name: provider, model_key: agent_config['model_key'])

    begin
      apply_provider_auth!(provider, agent_config)
    rescue StandardError => e
      puts e.message
      exit 1
    end
    debugger
    LlmGateway.build_provider(agent_config)
  end

  def resolve_model(_provider)
    @options[:model]
  end
end

AgentRunner.new.run if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
