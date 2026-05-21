module SessionEventSimulationHelper
  def simulate_three_messages(manager, user_text:, tool_id:, tool_name:, tool_input:, tool_result:)
    manager.push_message(
      role: 'user',
      content: [{ type: 'text', text: user_text }]
    )

    manager.push_message(
      role: 'assistant',
      content: [
        { type: 'text', text: 'I will inspect the file.' },
        { type: 'tool_use', id: tool_id, name: tool_name, input: tool_input }
      ]
    )

    manager.push_message(
      role: 'user',
      content: [{ type: 'tool_result', tool_use_id: tool_id, content: tool_result }]
    )
  end
end
