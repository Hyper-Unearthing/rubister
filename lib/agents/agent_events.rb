class Agent
  module Event
    class Base < BaseStruct
      EventType = Types::Coercible::Symbol.enum(
        :agent_start,
        :turn_start,
        :message_start,
        :message_update,
        :message_end,
        :tool_execution_start,
        :tool_execution_end,
        :turn_end,
        :agent_end
      )

      attribute :type, EventType
    end

    class Stream < Base
      StreamEventType =
        Types.Instance(AssistantStreamMessageEvent) |
        Types.Instance(AssistantStreamReasoningEvent) |
        Types.Instance(AssistantStreamEvent) |
        Types.Instance(AssistantToolStartEvent)

      attribute :stream_event, StreamEventType
    end

    class Message < Base
      attribute :message, Types.Instance(AssistantMessage)
    end

    class ToolCallResult < BaseStruct
      attribute :type, Types::String.default('tool_result'.freeze).enum('tool_result')
      attribute :tool_use_id, Types::String
      attribute(:content, Types::Array.of(Types::Any).constructor { |value| value.is_a?(Array) ? value : [value] })

      def to_h
        { role: 'user', content:
          [{
            type: type,
            tool_use_id: tool_use_id,
            content: content
          }] }
      end
    end

    class MessageUpdate < Stream
      attribute :type, Types::Coercible::Symbol.default(:message_update)
    end

    class MessageEnd < Message
      attribute :type, Types::Coercible::Symbol.default(:message_end)
    end

    class ToolExecutionStart < Base
      attribute :type, Types::Coercible::Symbol.default(:tool_execution_start)
      attribute :parameters, Types::Hash
    end

    class ToolExecutionEnd < Base
      attribute :type, Types::Coercible::Symbol.default(:tool_execution_end)
      attribute :parameters, Types::Hash
      attribute :result, Types::Hash
    end

    class TurnEnd < Message
      attribute :type, Types::Coercible::Symbol.default(:turn_end)
      attribute :tool_results, Types::Array.of(Types.Instance(ToolCallResult))
    end

    class AgentEnd < Base
      MessageType = Types.Instance(AssistantMessage) | Types.Instance(ToolCallResult)

      attribute :type, Types::Coercible::Symbol.default(:agent_end)
      attribute :messages, Types::Array.of(MessageType)
    end
  end
end
