require_relative '../gruv/base_agent'

# CloneAgent is a restricted variant of GruvAgent used for background clone tasks.
# Results are reported back to the main gruv via the inbox, not via send tools.
class CloneAgent < BaseGruvAgent
  SYSTEM_PROMPT_PATH = File.join(__dir__, 'prompt', 'clone-system-prompt.md')

  TOOLS = (BaseGruvAgent::TOOLS + [
    ReportCloneResultTool,
  ]).freeze
end
