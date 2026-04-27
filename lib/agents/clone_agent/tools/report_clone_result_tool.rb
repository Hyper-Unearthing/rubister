# frozen_string_literal: true

require 'json'
require_relative '../../../db/database_config'
require_relative '../../../db/clone_task'
require_relative '../../../db/inbox'

class ReportCloneResultTool < LlmGateway::Tool
  name 'report_clone_result'
  description 'Clone-only tool that reports the final clone result back into the inbox and marks the clone task completed.'
  input_schema({
    type: 'object',
    properties: {
      summary: { type: 'string', description: 'Final outcome summary.' },
      work_done: {
        type: 'array',
        items: { type: 'string' },
        description: 'List of meaningful work completed.'
      },
      created_files: {
        type: 'array',
        items: { type: 'string' },
        description: 'Paths of files created or modified.'
      },
      downloaded_files: {
        type: 'array',
        items: { type: 'string' },
        description: 'Paths of files downloaded during execution.'
      },
      follow_up_notes: { type: 'string', description: 'Optional notes for the main agent.' }
    },
    required: ['summary', 'work_done']
  })

  def execute(input)
    task_id = ENV['CLONE_TASK_ID']
    return JSON.generate({ ok: false, error: 'CLONE_TASK_ID missing' }) if task_id.nil? || task_id.strip.empty?

    DatabaseConfig.establish_connection!

    task = CloneTask.find(task_id)
    origin = Message.find(task.origin_inbox_message_id)
    inbox = Inbox.new(DatabaseConfig.db_path)

    summary = input[:summary]
    work_done = input[:work_done] || []
    created_files = input[:created_files] || []
    downloaded_files = input[:downloaded_files] || []
    follow_up_notes = input[:follow_up_notes]

    text = build_report_text(
      task_id: task.id,
      summary: summary,
      work_done: work_done,
      created_files: created_files,
      downloaded_files: downloaded_files,
      follow_up_notes: follow_up_notes
    )

    task.update!({
      state: 'completed',
      result_message: text,
      error_message: nil,
      completed_at: Time.now.utc.iso8601
    })

    inbox.insert_message(
      platform: origin.platform,
      channel_id: origin.channel_id,
      scope: 'clone_task',
      message: text,
      metadata: {
        task_id: task.id,
        origin_inbox_message_id: task.origin_inbox_message_id,
        pid: task.pid,
        state: 'completed',
        session_path: task.session_path,
        log_path: task.log_path,
        summary: summary,
        work_done: work_done,
        created_files: created_files,
        downloaded_files: downloaded_files,
        follow_up_notes: follow_up_notes
      }
    )

    JSON.generate({ ok: true, task_id: task.id, state: 'completed' })
  rescue => e
    JSON.generate({ ok: false, error: e.message })
  end

  private

  def build_report_text(task_id:, summary:, work_done:, created_files:, downloaded_files:, follow_up_notes:)
    sections = []
    sections << "Response from clone task #{task_id}:"
    sections << "Summary: #{summary}"

    if work_done.any?
      sections << 'Work done:'
      work_done.each { |item| sections << "- #{item}" }
    end

    if created_files.any?
      sections << 'Created/modified files:'
      created_files.each { |path| sections << "- #{path}" }
    end

    if downloaded_files.any?
      sections << 'Downloaded files:'
      downloaded_files.each { |path| sections << "- #{path}" }
    end

    if follow_up_notes && !follow_up_notes.strip.empty?
      sections << "Follow-up notes: #{follow_up_notes}"
    end

    sections.join("\n")
  end
end
