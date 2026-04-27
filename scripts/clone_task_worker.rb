#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'llm_gateway'
require_relative '../lib/db/database_config'
require_relative '../lib/db/clone_task'
require_relative '../lib/db/inbox'
require_relative '../lib/agents/clone_agent/agent'
require_relative '../lib/logging/events'
require_relative '../lib/logging/log_file_writer'
require_relative '../config/instance_file_scope'
require_relative '../agents/sessions/file_session_manager'
require_relative '../agents/sessions/agent_session'
require_relative '../config/runtime_config'
require_relative '../lib/provider_auth_helper'

class CloneTaskWorker
  include ProviderAuthHelper

  def initialize
    @options = {
      task_id: nil,
      provider: nil,
      model: nil
    }
  end

  def run
    parse_args
    DatabaseConfig.establish_connection!

    task = CloneTask.find(@options[:task_id])
    task.update!({ pid: Process.pid, state: 'processing', started_at: Time.now.utc.iso8601 })

    attach_task_log_writer(task)
    Events.set_context(process: 'clone_task_worker', role: 'clone_task_worker', pid: Process.pid)
    Events.notify('clone_task.start', { task_id: task.id, pid: Process.pid })

    ENV['CLONE_TASK_ID'] = task.id.to_s

    agent_session = build_agent_session(task)
    Events.tagged(task_id: task.id) do
      agent_session.run(task.message)
    end

    task.reload
    unless task.state == 'completed'
      raise 'Clone finished without calling report_clone_result'
    end

    Events.notify('clone_task.complete', { task_id: task.id })
  rescue => e
    handle_failure(e)
    raise
  ensure
    ENV.delete('CLONE_TASK_ID')
  end

  private

  def parse_args
    OptionParser.new do |opts|
      opts.banner = 'Usage: clone_task_worker.rb --task-id ID --provider KEY --model NAME'

      opts.on('--task-id ID', Integer, 'Clone task id (required)') { |value| @options[:task_id] = value }
      opts.on('--provider PROVIDER', 'Provider key (required)') { |value| @options[:provider] = value }
      opts.on('--model MODEL', 'Model key (required)') { |value| @options[:model] = value }
    end.parse!

    raise ArgumentError, 'Missing required --task-id' unless @options[:task_id]
    raise ArgumentError, 'Missing required --provider' unless @options[:provider] && !@options[:provider].strip.empty?
    raise ArgumentError, 'Missing required --model' unless @options[:model] && !@options[:model].strip.empty?
  end

  def attach_task_log_writer(task)
    FileUtils.mkdir_p(File.dirname(task.log_path))
    Events.subscribe(JsonlEventSubscriber.new(file_path: task.log_path))
  end

  def build_agent_session(task)
    provider_name = @options[:provider]
    model = @options[:model]

    RuntimeConfig.set(provider_name: provider_name, model_key: model)

    config = {
      'provider' => provider_name,
      'model_key' => resolve_model(model)
    }

    apply_provider_auth!(provider_name, config)

    client = LlmGateway.build_provider(config)

    session_manager = FileSessionManager.new(
      task.session_path,
      session_id: task.session_id,
      session_start: task.session_start
    )
    agent = CloneAgent.new(client)
    AgentSession.new(agent, session_manager)
  end

  def resolve_model(model)
    raise ArgumentError, 'Missing required --model' if model.strip.empty?

    model
  end


  def notify_failure_inbox(task:, payload:)
    origin = Message.find(task.origin_inbox_message_id)

    inbox = Inbox.new(DatabaseConfig.db_path)
    text = "Response from clone task #{task.id}: Task failed — #{payload}"

    inbox.insert_message(
      platform: origin.platform,
      channel_id: origin.channel_id,
      scope: 'clone_task',
      message: text,
      metadata: {
        task_id: task.id,
        origin_inbox_message_id: task.origin_inbox_message_id,
        pid: task.pid,
        state: 'failed',
        session_path: task.session_path,
        log_path: task.log_path
      }
    )
  end

  def handle_failure(error)
    return unless @options[:task_id]

    task = CloneTask.find_by(id: @options[:task_id])
    return unless task

    task.update!({
      state: 'failed',
      error_message: error.message,
      completed_at: Time.now.utc.iso8601
    })

    notify_failure_inbox(task: task, payload: error.message)
    Events.notify('clone_task.failed', {
      task_id: task.id,
      error: error.message,
      backtrace: error.backtrace
    })
  rescue => _e
    nil
  end
end

CloneTaskWorker.new.run
