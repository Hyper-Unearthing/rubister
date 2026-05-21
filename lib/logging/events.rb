# frozen_string_literal: true

require 'active_support'
require 'active_support/event_reporter'

module Events
  class << self
    def notify(name_or_object, payload = nil, **kwargs)
      reporter.notify(name_or_object, payload, caller_depth: 2, **kwargs)
    end

    def subscribe(subscriber, &filter)
      reporter.subscribe(subscriber, &filter)
    end

    def tagged(*args, **kwargs, &block)
      reporter.tagged(*args, **kwargs, &block)
    end

    def set_context(hash)
      reporter.set_context(hash)
    end

    def clear_context
      reporter.clear_context
    end

    def with_debug(&block)
      reporter.with_debug(&block)
    end

    def debug(name_or_object, payload = nil, **kwargs)
      reporter.debug(name_or_object, payload, caller_depth: 2, **kwargs)
    end

    private

    def reporter
      @reporter ||= begin
        ensure_filter_parameters!
        ActiveSupport::EventReporter.new
      end
    end

    def ensure_filter_parameters!
      return if ActiveSupport.respond_to?(:filter_parameters)

      ActiveSupport.singleton_class.attr_accessor :filter_parameters
      ActiveSupport.filter_parameters = []
    end
  end
end
