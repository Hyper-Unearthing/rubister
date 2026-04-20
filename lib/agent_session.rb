require_relative 'compaction_prompt'
require_relative 'events'
require_relative 'agent_events'

class AgentSession

  attr_reader :agent, :session_manager

  def initialize(agent, session_manager)
    @agent = agent
    @session_manager = session_manager

    @agent.transcript = model_input_messages
  end

  def run(message, &event_handler)
    @session_manager.push_message(
      role: 'user',
      content: [{ type: 'text', text: message }]
    )

    @agent.run(message) { |event| handle_agent_event(event, &event_handler) }
    compact if @session_manager.total_tokens > 20_000
  end

  def continue(&event_handler)
    @agent.continue { |event| handle_agent_event(event, &event_handler) }
    compact if @session_manager.total_tokens > 20_000
  end

  def compact
    session_manager.compaction(@agent.client)
    @agent.transcript = model_input_messages
  end

  def model_input_messages
    @session_manager.build_model_input_messages
  end

  private

  def handle_agent_event(event)
    case event
    when Agent::Event::MessageUpdate
    when Agent::Event::MessageEnd
      assistant_message = event.message.to_h
      @session_manager.push_message(assistant_message)
    when Agent::Event::TurnEnd
      tool_result_message = {
        role: 'user',
        content: event.tool_results.flat_map { |tool_result| tool_result.to_h[:content] }
      }
      @session_manager.push_message(tool_result_message)
    end

    unless event.type == :message_update
      payload = event.to_h
      payload.delete(:type)
      payload.delete(:tool_results)
      payload.delete(:result)
      Events.tagged(session_id: @session_manager.session_id) { Events.notify("agent.#{event.type}", payload) }
    end

    yield(event) if block_given?
  end
end
