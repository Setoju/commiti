# frozen_string_literal: true

require 'httparty'
require 'json'
require 'uri'

module Commiti
  class GoogleClient
    include HTTParty

    base_uri 'https://generativelanguage.googleapis.com'
    DEFAULT_MODEL = 'gemma-4-31b-it'
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_TIMEOUT_SECONDS = 180
    DEFAULT_OPEN_TIMEOUT_SECONDS = 10

    def initialize(config: Commiti::ConfigLoader.load)
      @config = config || {}
    end

    def generate(system:, user:, api_key: nil, model: nil, temperature: nil, timeout_seconds: nil, open_timeout_seconds: nil)
      settings = request_settings(
        api_key: api_key,
        model: model,
        temperature: temperature,
        timeout_seconds: timeout_seconds,
        open_timeout_seconds: open_timeout_seconds
      )
      response = generate_content(system: system, user: user, settings: settings)
      unless response.success?
        detail = extract_error(response.body)
        message = "Google AI error: #{response.code}"
        message = "#{message} - #{detail}" unless detail.empty?
        raise message
      end
      extract_generated_content(response.body)
    end

    private

    def normalize_model(model)
      value = model.to_s.strip
      normalized = value.sub(%r{\Amodels/}, '')
      normalized.empty? ? DEFAULT_MODEL : normalized
    end

    def normalize_api_key(value)
      key = value.to_s.strip
      return key unless key.empty?

      raise 'Google API key is missing. Set GOOGLE_API_KEY (or GEMINI_API_KEY) in your environment.'
    end

    def normalize_numeric(value, fallback)
      return fallback if value.nil? || value.to_s.strip.empty?

      yield(value)
    rescue ArgumentError
      fallback
    end

    def extract_error(body)
      parsed = JSON.parse(body.to_s)
      error = parsed['error']
      return error['message'].to_s.strip if error.is_a?(Hash)
      return error.to_s.strip unless error.nil?

      ''
    rescue JSON::ParserError
      ''
    end

    def extract_content(parsed)
      parts = parsed.dig('candidates', 0, 'content', 'parts')
      return '' unless parts.is_a?(Array)

      parts.map { |part| part['text'].to_s }.join.strip
    end

    def request_settings(api_key:, model:, temperature:, timeout_seconds:, open_timeout_seconds:)
      {
        api_key: normalize_api_key(api_key || @config[:google_api_key]),
        model: normalize_model(model || @config[:model]),
        temperature: normalize_numeric(temperature || @config[:temperature], DEFAULT_TEMPERATURE) { |raw| Float(raw) },
        timeout_seconds: normalize_numeric(timeout_seconds || @config[:timeout_seconds], DEFAULT_TIMEOUT_SECONDS) { |raw| Integer(raw) },
        open_timeout_seconds: normalize_numeric(open_timeout_seconds || @config[:open_timeout_seconds],
                                                DEFAULT_OPEN_TIMEOUT_SECONDS) { |raw| Integer(raw) }
      }
    end

    def extract_generated_content(body)
      parsed = JSON.parse(body.to_s)
      content = extract_content(parsed)
      raise 'Google AI error: response did not include generated text' if content.empty?

      content
    rescue JSON::ParserError => e
      raise "Google AI error: invalid JSON response (#{e.message})"
    end

    def generate_content(system:, user:, settings:)
      self.class.post(
        "/v1beta/models/#{URI.encode_www_form_component(settings[:model])}:generateContent",
        query: { key: settings[:api_key] },
        headers: { 'Content-Type' => 'application/json' },
        timeout: settings[:timeout_seconds],
        open_timeout: settings[:open_timeout_seconds],
        body: request_body(system: system, user: user, settings: settings).to_json
      )
    end

    def request_body(system:, user:, settings:)
      {
        systemInstruction: {
          parts: [{ text: system.to_s }]
        },
        generationConfig: {
          temperature: settings[:temperature]
        },
        contents: [
          {
            role: 'user',
            parts: [{ text: user.to_s }]
          }
        ]
      }
    end
  end
end
