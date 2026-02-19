require 'json'

class Agent
  def initialize(prompt_class, model, api_key, refresh_token: nil, expires_at: nil)
    @prompt_class = prompt_class
    @model = model
    @api_key = api_key
    @refresh_token = refresh_token
    @expires_at = expires_at
    @transcript = []
  end

  attr_reader :transcript

  def run(user_input, &block)
    @transcript << { role: 'user', content: [{ type: 'text', text: user_input }] }

    begin
      send_and_process(&block)
      yield({ type: :done }) if block_given?
    rescue StandardError => e
      yield({ type: :error, message: e.message }) if block_given?
      raise e
    end
  end

  private

  def send_and_process(&block)
    prompt = @prompt_class.new(@model, @transcript, @api_key, refresh_token: @refresh_token, expires_at: @expires_at)
    result = prompt.post do |event|
      case event[:type]
      when :text_delta, :thinking_delta
        yield(event) if block_given?
      end
    end

    response = result[:choices][0][:content]
    @transcript << { role: 'assistant', content: response }

    # Collect all tool uses
    tool_uses = response.select { |message| message[:type] == 'tool_use' }

    if tool_uses.any?
      tool_results = tool_uses.map do |message|
        yield({ type: :tool_use, id: message[:id], name: message[:name], input: message[:input] }) if block_given?
        result = handle_tool_use(message)

        tool_result = {
          type: 'tool_result',
          tool_use_id: message[:id],
          content: result
        }

        yield(tool_result) if block_given?
        tool_result
      end

      @transcript << { role: 'user', content: tool_results }
      send_and_process(&block)
    end

    response
  end

  def handle_tool_use(message)
    tool_class = @prompt_class.find_tool(message[:name])
    if tool_class
      tool = tool_class.new
      tool.execute(message[:input])
    else
      "Unknown tool: #{message[:name]}"
    end
  rescue StandardError => e
    "Error executing tool: #{e.message}"
  end
end
