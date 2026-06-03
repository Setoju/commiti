# frozen_string_literal: true

module Commiti
  class BaseClient
    def generate(system:, user:, model:, temperature: nil, timeout_seconds: nil, **opts)
      raise NotImplementedError, "#{self.class} must implement #generate"
    end

    private

    def normalize_float(value, fallback)
      return fallback if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def normalize_int(value, fallback)
      return fallback if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      fallback
    end
  end
end
