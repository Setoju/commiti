# frozen_string_literal: true

require 'httparty'
require 'json'

module Commiti
  class OpenAIClient < BaseClient
    include HTTParty

    base_uri 'https://api.openai.com'
    DEFAULT_MODEL = 'gpt-4o'
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_TIMEOUT_SECONDS = 180
    DEFAULT_OPEN_TIMEOUT_SECONDS = 10

    def initialize(config: {})
      @config = config || {}
    end

    def generate(system:, user:, model: nil, temperature: nil, timeout_seconds: nil, **_opts)
      api_key = ENV.fetch('OPENAI_API_KEY', '').strip
      resolved_model = model || @config[:model] || DEFAULT_MODEL
      resolved_temp  = normalize_float(temperature || @config[:temperature], DEFAULT_TEMPERATURE)
      resolved_timeout = normalize_int(timeout_seconds || @config[:timeout_seconds], DEFAULT_TIMEOUT_SECONDS)

      response = self.class.post(
        '/v1/chat/completions',
        headers: {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{api_key}"
        },
        timeout: resolved_timeout,
        open_timeout: DEFAULT_OPEN_TIMEOUT_SECONDS,
        body: {
          model: resolved_model,
          temperature: resolved_temp,
          messages: [
            { role: 'system', content: system.to_s },
            { role: 'user', content: user.to_s }
          ]
        }.to_json
      )

      unless response.success?
        detail = response.parsed_response.dig('error', 'message').to_s.strip
        msg = "OpenAI error: #{response.code}"
        msg = "#{msg} - #{detail}" unless detail.empty?
        raise msg
      end

      content = response.parsed_response.dig('choices', 0, 'message', 'content').to_s.strip
      raise 'OpenAI error: response did not include generated text' if content.empty?

      content
    end
  end
end
