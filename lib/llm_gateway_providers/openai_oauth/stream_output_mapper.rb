# frozen_string_literal: true

module OpenAiOAuth
  # Maps OpenAI Responses API SSE stream events to the normalized format
  # used by the agent (same shape as Claude's streaming events).
  #
  # Responses API event types:
  #   response.output_item.added   — new output item (message, function_call, reasoning)
  #   response.content_part.added  — content part added to a message
  #   response.output_text.delta   — text delta
  #   response.function_call_arguments.delta — tool call arguments delta
  #   response.output_item.done    — output item completed
  #   response.completed           — full response with usage
  class StreamOutputMapper
    def initialize
      @id = nil
      @model = nil
      @content = []
      @current_item_type = nil
      @current_tool = nil
      @usage = {}
    end

    # Process a raw SSE event, return normalized event or nil
    def map_event(sse_event)
      event_type = sse_event[:event]
      data = sse_event[:data]

      return nil if data == { raw: "[DONE]" }

      case event_type
      when "response.created"
        @id = data[:id] if data.is_a?(Hash)
        @model = data[:model] if data.is_a?(Hash)
        nil

      when "response.output_item.added"
        handle_output_item_added(data)

      when "response.content_part.added"
        # A content part added to a message item — we already created the text block
        nil

      when "response.output_text.delta"
        handle_text_delta(data)

      when "response.function_call_arguments.delta"
        handle_function_call_delta(data)

      when "response.output_item.done"
        handle_output_item_done(data)

      when "response.completed"
        handle_completed(data)

      when "response.reasoning_summary_text.delta"
        handle_thinking_delta(data)

      else
        nil
      end
    end

    # Return accumulated response in normalized shape
    def to_message
      {
        id: @id,
        model: @model,
        choices: [{
          content: finalized_content
        }],
        usage: @usage
      }
    end

    private

    def handle_output_item_added(data)
      return nil unless data.is_a?(Hash)

      item = data[:item] || data
      case item[:type]
      when "message"
        @current_item_type = "message"
        ensure_text_block
        nil
      when "function_call"
        @current_item_type = "function_call"
        @current_tool = {
          type: "tool_use",
          id: item[:call_id] || item[:id],
          name: item[:name] || "",
          input_json: +""
        }
        @content << @current_tool
        nil
      when "reasoning"
        @current_item_type = "reasoning"
        @content << { type: "thinking", thinking: +"" }
        nil
      else
        nil
      end
    end

    def handle_text_delta(data)
      return nil unless data.is_a?(Hash)

      delta = data[:delta]
      return nil unless delta

      ensure_text_block
      text_block = @content.select { |b| b[:type] == "text" }.last
      text_block[:text] << delta if text_block
      { type: :text_delta, text: delta }
    end

    def handle_thinking_delta(data)
      return nil unless data.is_a?(Hash)

      delta = data[:delta]
      return nil unless delta

      thinking_block = @content.select { |b| b[:type] == "thinking" }.last
      if thinking_block
        thinking_block[:thinking] << delta
        { type: :thinking_delta, text: delta }
      end
    end

    def handle_function_call_delta(data)
      return nil unless data.is_a?(Hash)

      delta = data[:delta]
      return nil unless delta && @current_tool

      @current_tool[:input_json] << delta
      nil
    end

    def handle_output_item_done(data)
      return nil unless data.is_a?(Hash)

      item = data[:item] || data
      if item[:type] == "function_call" && @current_tool
        @current_tool[:input] = parse_json(@current_tool[:input_json])
        @current_tool = nil
      end
      nil
    end

    def handle_completed(data)
      return nil unless data.is_a?(Hash)

      response = data[:response] || data
      if response[:usage]
        u = response[:usage]
        @usage = {
          input_tokens: u[:input_tokens] || 0,
          output_tokens: u[:output_tokens] || 0,
          total_tokens: u[:total_tokens] || 0
        }
      end
      @id ||= response[:id]
      @model ||= response[:model]
      nil
    end

    def ensure_text_block
      if @content.empty? || @content.last[:type] != "text"
        @content << { type: "text", text: +"" }
      end
    end

    def finalized_content
      @content.map do |block|
        case block[:type]
        when "text"
          { type: "text", text: block[:text] }
        when "tool_use"
          {
            type: "tool_use",
            id: block[:id],
            name: block[:name],
            input: block[:input] || parse_json(block[:input_json])
          }
        when "thinking"
          { type: "thinking", thinking: block[:thinking] }
        else
          block
        end
      end
    end

    def parse_json(str)
      return {} if str.nil? || str.empty?
      LlmGateway::Utils.deep_symbolize_keys(JSON.parse(str))
    rescue JSON::ParserError
      {}
    end
  end
end
