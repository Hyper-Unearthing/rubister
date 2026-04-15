require 'json'
require_relative 'eventable'
require 'debug'

class Agent < LlmGateway::Prompt
  include Eventable

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

  def run(user_input)
    append_user_message([user_input])
    continue
  end

  def continue
    response = send_and_process
    publish(:done, response)
  end

  def post
    @client.stream(
      prompt,
      tools: tools,
      system: system_prompt,
      reasoning: 'high'
    ) do |event|
      publish(event.type, event.to_h, stream_event_class: event.class.name)
    end
  end

  private

  def send_and_process
    result = post

    assistant_message = result.to_h
    publish(:message, assistant_message)
    transcript.push(assistant_message)

    tool_uses = result.content.select { |message| message.type == 'tool_use' }

    if tool_uses.any?
      tool_results = tool_uses.map do |message|
        execute_tool(message)
      end
      publish_tool_result(tool_results)
      send_and_process
    end

    assistant_message
  end

  def append_user_message(content)
    user_message = { role: 'user', content: content }
    transcript.push(user_message)
    user_message
  end

  def publish_tool_result(content)
    user_message = { role: 'user', content: content }
    publish(:message, user_message)
    transcript.push(user_message)
    user_message
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

    {
      type: 'tool_result',
      tool_use_id: tool_request.id,
      content: result
    }
  end
end
