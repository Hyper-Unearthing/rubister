require_relative 'tools/edit_tool'
require_relative 'tools/read_tool'
require_relative 'tools/todowrite_tool'
require_relative 'tools/bash_tool'
require_relative 'tools/grep_tool'

class Prompt < LlmGateway::Prompt
  def initialize(model, transcript, api_key, refresh_token: nil, expires_at: nil)
    super(model)
    @transcript = transcript
    @api_key = api_key
    @refresh_token = refresh_token
    @expires_at = expires_at
  end

  def prompt
    @transcript
  end

  def system_prompt
    <<~SYSTEM
      sup
    SYSTEM
  end

  def self.tools
    [EditTool, ReadTool, TodoWriteTool, BashTool, GrepTool]
  end

  def tools
    self.class.tools.map(&:definition)
  end

  def post
    LlmGateway::Client.chat(
      model,
      prompt,
      tools: tools,
      system: system_prompt,
      api_key: @api_key,
      refresh_token: @refresh_token,
      expires_at: @expires_at
    )
  end
end
