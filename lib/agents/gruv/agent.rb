require_relative 'base_agent'

class GruvAgent < BaseGruvAgent
  SYSTEM_PROMPT_PATH = File.join(__dir__, 'prompt', 'system-prompt.md')

  TOOLS = (BaseGruvAgent::TOOLS + [
    SendMessageTool,
    SendPhotoTool,
    SendVoiceTool,
    SendDocumentTool,
    SpawnCloneTaskTool,
    ReloadTool,
  ]).freeze
end
