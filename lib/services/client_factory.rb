# frozen_string_literal: true

module Commiti
  class ClientFactory
    SUPPORTED = %w[google openai anthropic ollama].freeze

    def self.build(config:)
      provider = (config[:provider] || 'google').to_s.strip.downcase

      raise ConfigError, "Unknown provider '#{provider}'. Supported: #{SUPPORTED.join(', ')}" unless SUPPORTED.include?(provider)

      case provider
      when 'openai'
        validate_env!('OPENAI_API_KEY')
        OpenAIClient.new(config: config)
      when 'anthropic'
        validate_env!('ANTHROPIC_API_KEY')
        AnthropicClient.new(config: config)
      when 'ollama'
        OllamaClient.new(config: config)
      else
        GoogleClient.new(config: config)
      end
    end

    def self.validate_env!(key)
      raise ConfigError, "#{key} is not set. Run: commiti init" if ENV.fetch(key, '').strip.empty?
    end
    private_class_method :validate_env!
  end
end
