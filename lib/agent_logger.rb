require_relative 'logging'

class AgentLogger
  def on_notify(event)
    return unless event[:name] == :message

    message = event[:payload]

    if message[:role] == 'assistant'
      @turn = (@turn || 0) + 1
      log_assistant_message(message)
      log_tool_calls(message)
    elsif message[:role] == 'user'
      log_tool_results(message)
    end
  end

  private

  def log_assistant_message(message)
    content = message[:content]
    content_types = content.map { |m| m[:type] }.uniq
    tool_names = content.select { |m| m[:type] == 'tool_use' }.map { |m| m[:name] }

    Logging.instance.notify('agent.llm_response', {
      turn: @turn,
      content_types: content_types,
      tool_names: tool_names,
      usage: message[:usage]
    })
  end

  def log_tool_calls(message)
    message[:content].select { |m| m[:type] == 'tool_use' }.each do |tool_use|
      Logging.instance.notify('agent.tool_call', {
        turn: @turn,
        tool: tool_use[:name],
        input: tool_use[:input]
      })
    end
  end

  def log_tool_results(message)
    message[:content].select { |m| m[:type] == 'tool_result' }.each do |tool_result|
      Logging.instance.notify('agent.tool_result', {
        turn: @turn,
        tool_use_id: tool_result[:tool_use_id],
        result: tool_result[:content][0, 500]
      })
    end
  end
end
