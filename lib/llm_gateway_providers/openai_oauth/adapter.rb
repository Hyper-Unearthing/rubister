# frozen_string_literal: true

require "llm_gateway"
require_relative "stream_output_mapper"

module OpenAiOAuth
  # Pass-through output mapper for streaming — the StreamOutputMapper
  # already returns the normalized format the agent expects.
  class PassthroughOutputMapper
    def self.map(data)
      data
    end
  end

  # Adapter that wraps the OpenAI OAuth Client with the OpenAI Responses API
  # input/output mappers from llm_gateway. This gives us the normalized
  # message format the agent expects.
  class Adapter < LlmGateway::Adapters::Adapter
    def initialize(client)
      super(
        client,
        input_mapper: LlmGateway::Adapters::OpenAi::Responses::InputMapper,
        output_mapper: PassthroughOutputMapper,
        stream_output_mapper: StreamOutputMapper
      )
    end
  end
end
