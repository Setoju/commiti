# frozen_string_literal: true

require 'httparty'
require 'json'

module Commiti
  class OllamaClient < BaseClient
    include HTTParty

    DEFAULT_MODEL = 'llama3.2'
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_TIMEOUT_SECONDS = 180
    DEFAULT_OPEN_TIMEOUT_SECONDS = 10
    DEFAULT_BASE_URL = 'http://localhost:11434'

    def initialize(config: {})
      @config = config || {}
      @base_url = ENV.fetch('OLLAMA_BASE_URL', DEFAULT_BASE_URL).strip
    end

    def generate(system:, user:, model: nil, temperature: nil, timeout_seconds: nil, **opts)
      resolved_model   = model || @config[:model] || DEFAULT_MODEL
      resolved_temp    = normalize_float(temperature || @config[:temperature], DEFAULT_TEMPERATURE)
      resolved_timeout = normalize_int(timeout_seconds || @config[:timeout_seconds], DEFAULT_TIMEOUT_SECONDS)

      response = self.class.post(
        "#{@base_url}/api/chat",
        headers: { 'Content-Type' => 'application/json' },
        timeout: resolved_timeout,
        open_timeout: DEFAULT_OPEN_TIMEOUT_SECONDS,
        body: {
          model: resolved_model,
          stream: false,
          options: { temperature: resolved_temp },
          messages: [
            { role: 'system', content: system.to_s },
            { role: 'user', content: user.to_s }
          ]
        }.to_json
      )

      raise "Ollama error: #{response.code} - #{response.body.to_s.strip}" unless response.success?

      content = response.parsed_response.dig('message', 'content').to_s.strip
      raise 'Ollama error: response did not include generated text' if content.empty?

      content
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
