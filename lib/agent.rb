require 'json'
require 'debug'

class Agent < LlmGateway::Prompt
  attr_reader :client
  attr_accessor :transcript

  def initialize(client, transcript: [])
    super(client.client.model_key)
    @client = client
    @transcript = transcript
  end

  def prompt
    transcript
  end

  def self.tools
    self::TOOLS
  end

  def self.find_tool(name)
    tools.find { |tool| tool.tool_name == name }
  end

  def tools
    self.class.tools.map(&:definition)
  end

  def run(user_input, &block)
    append_user_message([user_input])
    continue(&block)
  end

  def continue(&block)
    messages = []

    emit(Event::Base.new(type: :agent_start), &block)
    send_and_process(messages:, &block)
  end

  def post(&block)
    @client.stream(
      prompt,
      tools: tools,
      system: system_prompt,
      reasoning: 'high',
      &block
    )
  end

  private

  def send_and_process(messages:, &block)
    result = post do |event|
      emit(Event::MessageUpdate.new(stream_event: event), &block)
    end

    emit(Event::Base.new(type: :turn_start), &block)
    emit(Event::Base.new(type: :message_start), &block)

    assistant_message = result
    transcript << assistant_message.to_h
    messages << assistant_message

    emit(Event::MessageEnd.new(message: assistant_message), &block)

    tool_results = result.content.select { |message| message.type == 'tool_use' }.map do |message|
      parameters = message.to_h
      emit(Event::ToolExecutionStart.new(parameters: parameters), &block)
      tool_result = execute_tool(message)
      emit(Event::ToolExecutionEnd.new(parameters: parameters, result: tool_result.to_h), &block)
      transcript << tool_result.to_h
      messages.concat([tool_result])
      tool_result
    end

    turn_end_event = Event::TurnEnd.new(message: assistant_message, tool_results: tool_results)
    emit(turn_end_event, &block)

    return send_and_process(messages:, &block) if tool_results.length.positive?

    emit(Event::AgentEnd.new(messages: messages), &block)
    assistant_message
  end

  def append_user_message(content)
    user_message = { role: 'user', content: content }
    transcript.push(user_message)
    user_message
  end

  def emit(event, &block)
    return unless block

    block.call(event)
  end

  def execute_tool(tool_request)
    tool_name = tool_request.name
    tool_input = tool_request.input
    tool_class = self.class.find_tool(tool_name)

    result = begin
      if tool_class
        tool_class.new.execute(tool_input)
      else
        "Unknown tool: #{tool_name}"
      end
    rescue StandardError => e
      "Error executing tool: #{e.message}"
    end

    Event::ToolCallResult.new(
      type: 'tool_result',
      tool_use_id: tool_request.id,
      content: result
    )
  end
end

require_relative 'agent_events'
