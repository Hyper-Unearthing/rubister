require 'json'
require 'securerandom'
require 'time'
require 'active_record'
require_relative 'base_session_manager'
require_relative '../database_config'

class SqlSessionManager < BaseSessionManager
  SESSION_START = 'continuous'.freeze

  def initialize(channel_id:)
    super(nil)
    @session_id = channel_id
    @session_start = SESSION_START
    @events = []

    DatabaseConfig.establish_connection!
  end

  def fix_missing_tool_result(tool_use_id)
    sql = <<~SQL
      SELECT event_id, data_json
      FROM session_events
      WHERE session_id = ?
        AND session_start = ?
        AND event_type = 'message'
        AND data_json LIKE ?
      ORDER BY position ASC
    SQL

    rows = execute_sql(sql, @session_id, @session_start, "%\"id\":\"#{tool_use_id}\"%") { |result| result.to_a }
    updated_count = 0

    rows.each do |row|
      data = parse_json(row['data_json'])
      tool_use = data[:content].find { |block| block[:type] == 'tool_use' && block[:id] == tool_use_id }
      next unless tool_use

      replacement_text = "you attempted to use a tool but it broke: #{tool_use[:name]}, parameters: #{tool_use[:input].inspect}"
      updated_data = {
        role: 'user',
        content: [
          {
            type: 'text',
            text: replacement_text
          }
        ]
      }

      persist_event_data_by_id(row['event_id'], updated_data)
      updated_count += 1
    end

    updated_count
  end

  private

  def fetch_latest_transcript
    compaction_data = latest_compaction_data
    first_kept_entry_id = compaction_data && compaction_data[:first_kept_entry_id]
    messages = select_message_transcript(first_kept_entry_id)

    { messages: messages, compaction_data: compaction_data }
  end

  def message_entries
    sql = <<~SQL
      SELECT event_id, parent_id, timestamp, usage_json, data_json
      FROM session_events
      WHERE session_id = ? AND session_start = ? AND event_type = 'message'
      ORDER BY position ASC
    SQL

    rows = execute_sql(sql, @session_id, @session_start) { |result| result.to_a }

    rows.map do |row|
      {
        id: row['event_id'],
        parent_id: row['parent_id'],
        timestamp: row['timestamp'],
        type: 'message',
        usage: parse_json(row['usage_json']),
        data: parse_json(row['data_json'])
      }
    end
  end

  def parent_id_for_new_entry
    last_event_id
  end

  def persist_entry(entry)
    sql = <<~SQL
      INSERT INTO session_events (
        session_id,
        session_start,
        position,
        event_id,
        parent_id,
        timestamp,
        event_type,
        usage_json,
        data_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL

    execute_sql(
      sql,
      @session_id,
      @session_start,
      next_position,
      entry[:id],
      entry[:parent_id],
      entry[:timestamp],
      entry[:type],
      entry[:usage] ? JSON.generate(entry[:usage]) : nil,
      JSON.generate(entry[:data])
    ) { nil }
  end

  def persist_event_data_by_id(event_id, data)
    sql = <<~SQL
      UPDATE session_events
      SET data_json = ?
      WHERE session_id = ? AND session_start = ? AND event_id = ?
    SQL

    execute_sql(sql, JSON.generate(data), @session_id, @session_start, event_id) { nil }
  end

  def last_summary
    latest_compaction_data&.dig(:summary)
  end

  def last_compaction_entry
    sql = <<~SQL
      SELECT event_id, parent_id, timestamp, usage_json, data_json
      FROM session_events
      WHERE session_id = ? AND session_start = ? AND event_type = 'compaction'
      ORDER BY position DESC
      LIMIT 1
    SQL

    row = execute_sql(sql, @session_id, @session_start) { |result| result.next }
    return nil unless row

    {
      id: row['event_id'],
      parent_id: row['parent_id'],
      timestamp: row['timestamp'],
      type: 'compaction',
      usage: parse_json(row['usage_json']),
      data: parse_json(row['data_json'])
    }
  end

  def latest_compaction_data
    last_compaction_entry&.dig(:data)
  end

  def select_message_transcript(first_kept_entry_id)
    sql = <<~SQL
      SELECT data_json
      FROM session_events
      WHERE session_id = ?
        AND session_start = ?
        AND event_type = 'message'
        AND position >= COALESCE((
          SELECT position
          FROM session_events
          WHERE session_id = ?
            AND session_start = ?
            AND event_id = ?
          LIMIT 1
        ), 0)
      ORDER BY position ASC
    SQL

    rows = execute_sql(
      sql,
      @session_id,
      @session_start,
      @session_id,
      @session_start,
      first_kept_entry_id
    ) { |result| result.to_a }

    rows.map { |row| parse_json(row['data_json']) }
  end

  def next_position
    sql = 'SELECT COALESCE(MAX(position), 0) + 1 AS next_position FROM session_events WHERE session_id = ? AND session_start = ?'
    row = execute_sql(sql, @session_id, @session_start) { |result| result.next }

    row ? row['next_position'] : 1
  end

  def last_event_id
    sql = <<~SQL
      SELECT event_id
      FROM session_events
      WHERE session_id = ? AND session_start = ?
      ORDER BY position DESC
      LIMIT 1
    SQL

    row = execute_sql(sql, @session_id, @session_start) { |result| result.next }
    row ? row['event_id'] : nil
  end

  def execute_sql(sql, *params)
    db = ActiveRecord::Base.connection.raw_connection
    statement = db.prepare(sql)
    result = statement.execute(*params)
    yield result
  ensure
    begin
      result&.close if result.respond_to?(:close)
    rescue StandardError
      nil
    end

    begin
      statement&.close
    rescue StandardError
      nil
    end
  end

  def parse_json(value)
    return nil if value.nil?

    JSON.parse(value, symbolize_names: true)
  end
end
