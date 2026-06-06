# frozen_string_literal: true

module RuntimeConfig
  class << self
    attr_accessor :provider_name, :model

    def set(provider_name:, model: nil)
      @provider_name = provider_name
      @model = model
    end

    # Backward-compatible reader for callers that still refer to model_key.
    def model_key
      model
    end
  end
end
