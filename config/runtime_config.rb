# frozen_string_literal: true

module RuntimeConfig
  class << self
    attr_accessor :provider_name, :model_key

    def set(provider_name:, model_key: nil)
      @provider_name = provider_name
      @model_key = model_key
    end
  end
end
