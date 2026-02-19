require_relative 'tools/edit_tool'
require_relative 'tools/read_tool'
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
    cloned_history = Marshal.load(Marshal.dump(@transcript))
    if (last_content = cloned_history.last&.dig('content')) && last_content.is_a?(Array) && last_content.last
      last_content.last['cache_control'] = { 'type': 'ephemeral' }
    end
    cloned_history.map { |h| deep_symbolize_keys(h) }
  end

  def system_prompt
    content = <<~SYSTEM
      You are a coding assistant with access to tools: Read, Edit, Bash, and Grep.
      When the user asks you to modify code, use your tools to find files, read them,
      and make changes. Do not ask the user for file paths — search for them yourself.
      Act, don't ask.
    SYSTEM
    [{ role: 'system', content: content, cache_control: { 'type': 'ephemeral' } }]
  end

  def self.tools
    [EditTool, ReadTool, BashTool, GrepTool]
  end

  def tools
    self.class.tools.map(&:definition)
  end

  def post(&block)
    LlmGateway::Client.chat(
      model,
      prompt,
      tools: tools,
      system: system_prompt,
      api_key: @api_key,
      refresh_token: @refresh_token,
      expires_at: @expires_at,
      &block
    )
  end

  private

  def deep_symbolize_keys(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = deep_symbolize_keys(v) }
    when Array
      obj.map { |e| deep_symbolize_keys(e) }
    else
      obj
    end
  end
end
