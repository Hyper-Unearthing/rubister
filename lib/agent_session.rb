require_relative 'compaction_prompt'
require_relative 'logging'
require_relative 'agent_logger'

class AgentSession
  attr_reader :agent, :session_manager

  def initialize(agent, session_manager)
    @agent = agent
    @session_manager = session_manager

    @agent.subscribe(@session_manager)
    @agent.subscribe(AgentLogger.new)
    @agent.transcript = model_input_messages
  end

  def run(message)
    @session_manager.push_message(
      role: 'user',
      content: [{ type: 'text', text: message }]
    )

    @agent.run(message)
    compact if @session_manager.total_tokens > 20_000
  end

  def continue
    @agent.continue
    compact if @session_manager.total_tokens > 20_000
  end

  def compact
    session_manager.compaction(@agent.client)
    @agent.transcript = model_input_messages
  end

  def model_input_messages
    @session_manager.build_model_input_messages
  end
end
