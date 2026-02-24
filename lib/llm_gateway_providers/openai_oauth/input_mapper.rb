# frozen_string_literal: true

require "json"
require "llm_gateway"

module OpenAiOAuth
  # Input mapper for OpenAI OAuth Responses provider.
  #
  # Codex Responses rejects assistant replay blocks of type `thinking`,
  # `reasoning`, and `summary_text` for this endpoint/account mode.
  # Keep transcript reasoning internally, but strip it when sending input.
  class InputMapper < LlmGateway::Adapters::OpenAi::Responses::InputMapper
    def self.map_messages(messages)
      return messages unless messages.is_a?(Array)

      mapper = message_mapper
      stripped_messages = strip_reasoning_blocks(messages)

      mapped = stripped_messages.each_with_object([]) do |msg, acc|
        next unless msg.is_a?(Hash)

        role = msg[:role]
        content = msg[:content]

        if role == "user" && tool_result_message?(content)
          # Responses API expects tool results as top-level input items.
          content.each { |part| acc << mapper.map_content(part) }
          next
        end

        if role == "assistant" && content.is_a?(Array)
          assistant_items = map_assistant_content(content, mapper)
          acc.concat(assistant_items)
          next
        end

        mapped_content =
          if content.is_a?(Array)
            content.map { |part| mapper.map_content(part) }
          else
            [mapper.map_content(content)]
          end

        acc << {
          role: role,
          content: mapped_content
        }
      end

      normalize_assistant_content_types(mapped)
    end

    def self.strip_reasoning_blocks(obj)
      case obj
      when Array
        obj.map { |item| strip_reasoning_blocks(item) }.compact
      when Hash
        type = obj[:type]
        return nil if ["thinking", "reasoning", "summary_text"].include?(type)

        obj.each_with_object({}) do |(k, v), acc|
          normalized = strip_reasoning_blocks(v)
          acc[k] = normalized unless normalized.nil?
        end
      else
        obj
      end
    end

    def self.normalize_assistant_content_types(messages)
      return messages unless messages.is_a?(Array)

      messages.map do |msg|
        next msg unless msg.is_a?(Hash) && msg[:role] == "assistant" && msg[:content].is_a?(Array)

        normalized_content = msg[:content].map do |part|
          if part.is_a?(Hash) && part[:type] == "input_text"
            part.merge(type: "output_text")
          else
            part
          end
        end

        msg.merge(content: normalized_content)
      end
    end

    def self.tool_result_message?(content)
      content.is_a?(Array) && content.first.is_a?(Hash) && content.first[:type] == "tool_result"
    end

    def self.map_assistant_content(content, mapper)
      text_parts = []
      items = []

      content.each do |part|
        next unless part.is_a?(Hash)

        case part[:type]
        when "tool_use", "function_call"
          call_id = part[:id] || part[:call_id]
          arguments = part[:input] || part[:arguments] || {}
          arguments = JSON.generate(arguments) unless arguments.is_a?(String)

          items << {
            type: "function_call",
            call_id: call_id,
            name: part[:name],
            arguments: arguments
          }.compact
        when "text", "input_text", "output_text"
          text_parts << {
            type: "output_text",
            text: part[:text].to_s
          }
        else
          mapped = mapper.map_content(part)
          text_parts << mapped if mapped
        end
      end

      if text_parts.any?
        items.unshift({
          role: "assistant",
          content: text_parts
        })
      end

      items
    end

    private_class_method :strip_reasoning_blocks, :normalize_assistant_content_types,
      :tool_result_message?, :map_assistant_content
  end
end
