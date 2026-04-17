require_relative '../lib/logging'
require_relative '../lib/log_file_writer'
require_relative '../lib/instance_file_scope'
require_relative '../lib/format_stream'
require_relative '../lib/agent'
require_relative '../lib/agent_session'
require_relative '../lib/coding_agent'
require_relative '../lib/sessions/file_session_manager'

class MessageMode
  def initialize(client, session_file)
    @agent_session = build_session(client, session_file)
    @formatter = Formatter.new

    log_file_writer = LogFileWriter.new(file_path: InstanceFileScope.path('message_logs.jsonl'),
                                        process_name: self.class.name.gsub(/([a-z0-9])([A-Z])/, '\\1_\\2').downcase)
    Logging.instance.attach(log_file_writer)
  end

  def run(message)
    @agent_session.run(message) { |event| @formatter.render_agent_event(event) }
  end

  private

  def build_session(client, session_file)
    agent = CodingAgent.new(client)
    AgentSession.new(agent, FileSessionManager.new(session_file))
  end
end
