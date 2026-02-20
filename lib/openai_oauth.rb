# frozen_string_literal: true

require_relative "llm_gateway_providers/openai_oauth/oauth_flow"
require_relative "llm_gateway_providers/openai_oauth/token_manager"
require_relative "llm_gateway_providers/openai_oauth/client"
require_relative "llm_gateway_providers/openai_oauth/stream_output_mapper"
require_relative "llm_gateway_providers/openai_oauth/adapter"

module OpenAiOAuth
  # Run the interactive OAuth login flow.
  # Returns { access_token:, refresh_token:, expires_at:, account_id: }
  def self.login
    flow = OAuthFlow.new
    flow.login
  end
end

# Register as a provider so it can be built via LlmGateway.build_provider
LlmGateway::ProviderRegistry.register("openai_oauth_responses",
  client: OpenAiOAuth::Client,
  adapter: OpenAiOAuth::Adapter)
