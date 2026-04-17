require_relative 'compaction_prompt'
require_relative 'logging'
require_relative 'agent_logger'
require_relative 'eventable'
require_relative 'agent_events'

class AgentSession
  include Eventable

  attr_reader :agent, :session_manager

  def initialize(agent, session_manager)
    @agent = agent
    @session_manager = session_manager
    @agent_logger = AgentLogger.new

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
    publish(event.type, event.to_h) if event.respond_to?(:type) && event.respond_to?(:to_h) && !event.is_a?(Agent::Event::MessageUpdate)

    case event
    when Agent::Event::MessageUpdate
      stream_event = event.stream_event
      publish(stream_event.type, stream_event.to_h)
      publish(:message_update, stream_event.to_h)
    when Agent::Event::MessageEnd
      assistant_message = event.message.to_h
      @session_manager.push_message(assistant_message)
      @agent_logger.log_message(assistant_message)
      publish(:message, assistant_message)
    when Agent::Event::TurnEnd
      tool_result_message = {
        role: 'user',
        content: event.tool_results.flat_map { |tool_result| tool_result.to_h[:content] }
      }
      @session_manager.push_message(tool_result_message)
      @agent_logger.log_message(tool_result_message)
      publish(:message, tool_result_message)
    when Agent::Event::AgentEnd
      publish(:done, event.to_h)
    end

    yield(event) if block_given?
  end
end
