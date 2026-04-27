require_relative '../lib/logging/events'
require_relative '../lib/logging/log_file_writer'
require_relative '../config/instance_file_scope'
require_relative '../lib/format_stream'
require_relative '../lib/agents/agent'
require_relative '../agents/sessions/agent_session'
require_relative '../lib/agents/coding_agent'
require_relative '../agents/sessions/file_session_manager'

class MessageMode
  def initialize(client, session_file)
    @agent_session = build_session(client, session_file)
    @formatter = Formatter.new

    process_name = self.class.name.gsub(/([a-z0-9])([A-Z])/, '\\1_\\2').downcase
    log_file_writer = JsonlEventSubscriber.new(file_path: InstanceFileScope.path('message_logs.jsonl'), process_name: process_name)
    Events.subscribe(log_file_writer)
    Events.set_context(process: process_name, role: ENV['GRUV_ROLE'] || 'message_mode', pid: Process.pid)
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
