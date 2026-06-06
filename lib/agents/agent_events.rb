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
        Types.Instance(AssistantStreamMessageEndEvent) |
        Types.Instance(AssistantStreamReasoningEvent) |
        Types.Instance(AssistantStreamEvent) |
        Types.Instance(AssistantToolStartEvent) |
        Types.Instance(AssistantToolResultStartEvent)

      attribute :stream_event, StreamEventType
    end

    class Message < Base
      attribute :message, Types.Instance(AssistantMessage)
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
      attribute :result, Types.Instance(::ToolResult)
    end

    class TurnEnd < Message
      attribute :type, Types::Coercible::Symbol.default(:turn_end)
      attribute :tool_results, Types::Array.of(Types.Instance(::ToolResult))
    end

    class AgentEnd < Base
      MessageType = Types.Instance(AssistantMessage) | Types.Instance(::ToolResult) | Types::Hash

      attribute :type, Types::Coercible::Symbol.default(:agent_end)
      attribute :messages, Types::Array.of(MessageType)
    end
  end
end
