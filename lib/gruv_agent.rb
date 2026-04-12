require_relative 'base_gruv_agent'

class GruvAgent < BaseGruvAgent
  SYSTEM_PROMPT_PATH = File.join(__dir__, 'prompt', 'system-prompt.md')

  TOOLS = ALL_TOOLS
    .reject { |klass| klass == ReportCloneResultTool }
    .freeze
end
