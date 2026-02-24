class AgentSession
  attr_reader :agent, :session_manager

  def initialize(agent, session_manager)
    @agent = agent
    @session_manager = session_manager

    @agent.subscribe(@session_manager)
    @agent.transcript = raw_transcript
  end

  def run(message)
    @agent.run(message)
  end

  def raw_transcript
    @session_manager.current_transcript || []
  end
end
