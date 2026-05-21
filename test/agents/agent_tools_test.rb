require 'minitest/autorun'
require 'llm_gateway'
require_relative '../../lib/agents/gruv/agent'
require_relative '../../lib/agents/clone_agent/agent'
require_relative '../../lib/agents/coding_agent/agent'

class AgentToolsTest < Minitest::Test
  def test_gruv_agent_tools
    assert_equal %w[
      GetMe
      SendDocument
      SendMessage
      SendPhoto
      SendVoice
      bash
      edit
      read
      reload
      spawn_clone_task
      sql
      transcribe_voice
      write
    ].sort, GruvAgent::TOOLS.map(&:name).sort
  end

  def test_clone_agent_tools
    assert_equal %w[
      GetMe
      bash
      edit
      read
      report_clone_result
      sql
      transcribe_voice
      write
    ].sort, CloneAgent::TOOLS.map(&:name).sort
  end

  def test_coding_agent_tools
    assert_equal %w[
      bash
      edit
      read
      write
    ].sort, CodingAgent::TOOLS.map(&:name).sort
  end

  def test_reload_is_only_available_to_gruv
    assert_includes GruvAgent::TOOLS.map(&:name), 'reload'
    refute_includes CloneAgent::TOOLS.map(&:name), 'reload'
    refute_includes CodingAgent::TOOLS.map(&:name), 'reload'
  end
end
