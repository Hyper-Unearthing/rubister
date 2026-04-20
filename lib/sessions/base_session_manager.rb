require 'securerandom'
require 'time'
require_relative 'concerns/basic_compaction'
require_relative '../usage_normalizer'

class BaseSessionManager
  include BasicCompaction

  attr_reader :session_id, :session_start
  attr_accessor :model

  def push_message(payload)
    normalized_payload = payload.merge(usage: message_usage(payload))

    push_entry(
      type: 'message',
      data: normalized_payload
    )
  end

  def push_entry(entry)
    id = SecureRandom.uuid
    new_entry = {
      id: id,
      parent_id: parent_id_for_new_entry,
      timestamp: Time.now.iso8601,
      **entry
    }

    persist_entry(new_entry)
    new_entry
  end

  def active_messages
    compaction_event = last_compaction_entry
    messages = if compaction_event
                 compaction_index = events.index(compaction_event)
                 events[(compaction_index + 1)..].select { |event| event[:type] == 'message' }
               else
                 message_events
               end

    messages.map { |event| event[:data] }
  end

  def build_model_input_messages
    return active_messages unless last_compaction_entry

    summary_message = {
      role: 'assistant',
      content: [
        {
          type: 'text',
          text: last_compaction_entry.dig(:data, :summary)
        }
      ]
    }

    [summary_message, *active_messages]
  end

  def total_tokens
    entry = message_events.reverse.find { |event| event.dig(:data, :usage, :total_tokens) }
    entry&.dig(:data, :usage, :total_tokens) || 0
  end

  private

  def parent_id_for_new_entry
    events.length.positive? ? events.last[:id] : nil
  end

  def message_events
    events.select { |event| event[:type] == 'message' }
  end

  def last_compaction_entry
    events.reverse.find { |event| event[:type] == 'compaction' }
  end

  def message_usage(message)
    UsageNormalizer.normalize(message[:usage])
  end

  def persist_entry(entry)
    events << entry
  end

  def new_session_event
    @session_id = SecureRandom.uuid
    @session_start = Time.now.strftime('%Y%m%d_%H%M%S')
    { type: 'session', id: session_id, timestamp: session_start }
  end

  def events
    @events ||= [new_session_event]
  end
end
