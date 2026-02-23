# frozen_string_literal: true

require "llm_gateway"

module OpenAiOAuth
  # Input mapper for OpenAI OAuth Responses provider.
  #
  # Codex Responses rejects assistant replay blocks of type `thinking`,
  # `reasoning`, and `summary_text` for this endpoint/account mode.
  # Keep transcript reasoning internally, but strip it when sending input.
  class InputMapper < LlmGateway::Adapters::OpenAi::Responses::InputMapper
    def self.map_messages(messages)
      mapped = super(strip_reasoning_blocks(messages))
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

    private_class_method :strip_reasoning_blocks, :normalize_assistant_content_types
  end
end
