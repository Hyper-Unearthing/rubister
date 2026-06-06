require 'json'
require 'debug'

class Agent < LlmGateway::Prompt
  attr_reader :client
  attr_accessor :transcript

  def initialize(client, model: RuntimeConfig.model)
    super(provider: client, model: model, reasoning: 'high')
    @client = client
    @transcript = []
  end

  def prompt
    transcript
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

  def stream_options
    {
      tools: tools,
      system: system_prompt,
      reasoning: reasoning,
      model: model,
      cache_key: cache_key,
      cache_retention: cache_retention
    }.compact
  end

  def post(&block)
    @client.stream(
      prompt,
      **stream_options,
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
      tool_result = execute_tool_request(message)
      emit(Event::ToolExecutionEnd.new(parameters: parameters, result: tool_result), &block)
      tool_result
    end

    if tool_results.any?
      tool_result_message = {
        role: 'user',
        content: tool_results.map(&:to_h)
      }
      transcript << tool_result_message
      messages << tool_result_message
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

  def execute_tool_request(tool_request)
    find_and_execute_tool(tool_request)
  end
end

require_relative 'agent_events'
