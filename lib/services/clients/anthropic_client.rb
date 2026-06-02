# frozen_string_literal: true

require 'httparty'
require 'json'

module Commiti
  class AnthropicClient < BaseClient
    include HTTParty

    base_uri 'https://api.anthropic.com'
    DEFAULT_MODEL = 'claude-sonnet-4-6'
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_TIMEOUT_SECONDS = 180
    DEFAULT_OPEN_TIMEOUT_SECONDS = 10
    MAX_TOKENS = 1024

    def initialize(config: {})
      @config = config || {}
    end

    def generate(system:, user:, model: nil, temperature: nil, timeout_seconds: nil, **opts)
      api_key = ENV.fetch('ANTHROPIC_API_KEY', '').strip
      resolved_model   = model || @config[:model] || DEFAULT_MODEL
      resolved_temp    = normalize_float(temperature || @config[:temperature], DEFAULT_TEMPERATURE)
      resolved_timeout = normalize_int(timeout_seconds || @config[:timeout_seconds], DEFAULT_TIMEOUT_SECONDS)

      response = self.class.post(
        '/v1/messages',
        headers: {
          'Content-Type' => 'application/json',
          'x-api-key' => api_key,
          'anthropic-version' => '2023-06-01'
        },
        timeout: resolved_timeout,
        open_timeout: DEFAULT_OPEN_TIMEOUT_SECONDS,
        body: {
          model: resolved_model,
          max_tokens: MAX_TOKENS,
          temperature: resolved_temp,
          system: system.to_s,
          messages: [{ role: 'user', content: user.to_s }]
        }.to_json
      )

      unless response.success?
        detail = response.parsed_response.dig('error', 'message').to_s.strip
        msg = "Anthropic error: #{response.code}"
        msg = "#{msg} - #{detail}" unless detail.empty?
        raise msg
      end

      content = response.parsed_response.dig('content', 0, 'text').to_s.strip
      raise 'Anthropic error: response did not include generated text' if content.empty?

      content
    end

  end
end
