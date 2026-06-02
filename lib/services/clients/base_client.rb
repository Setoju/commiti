# frozen_string_literal: true

module Commiti
  class BaseClient
    def generate(system:, user:, model:, temperature: nil, timeout_seconds: nil, **opts)
      raise NotImplementedError, "#{self.class} must implement #generate"
    end
  end
end
