class Agent
  def initialize(prompt_class, model, api_key, refresh_token: nil, expires_at: nil)
    @prompt_class = prompt_class
    @model = model
    @api_key = api_key
    @refresh_token = refresh_token
    @expires_at = expires_at
    @transcript = []
  end

  def run(user_input, &block)
    @transcript << { role: 'user', content: [{ type: 'text', text: user_input }] }

    begin
      prompt = @prompt_class.new(@model, @transcript, @api_key, refresh_token: @refresh_token, expires_at: @expires_at)
      result = prompt.post
      process_response(result[:choices][0][:content], &block)
    rescue StandardError => e
      yield({ type: 'error', message: e.message }) if block_given?
      raise e
    end
  end

  private

  def process_response(response, &block)
    @transcript << { role: 'assistant', content: response }

    # Yield all messages to the block first
    response.each do |message|
      yield(message) if block_given?
    end

    # Collect all tool uses
    tool_uses = response.select { |message| message[:type] == 'tool_use' }

    # If there are any tool uses, execute them all and make a single follow-up call
    if tool_uses.any?
      tool_results = tool_uses.map do |message|
        result = handle_tool_use(message)

        tool_result = {
          type: 'tool_result',
          tool_use_id: message[:id],
          content: result
        }

        yield(tool_result) if block_given?
        tool_result
      end

      # Add all tool results to transcript in a single user message
      @transcript << { role: 'user', content: tool_results }

      # Make a single follow-up call with all tool results
      follow_up_prompt = @prompt_class.new(@model, @transcript, @api_key, refresh_token: @refresh_token,
                                                                          expires_at: @expires_at)
      follow_up = follow_up_prompt.post

      process_response(follow_up[:choices][0][:content], &block) if follow_up[:choices][0][:content]
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
