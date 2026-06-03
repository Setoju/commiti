# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::ClientFactory do
  describe '.build' do
    context 'google (default)' do
      it 'returns GoogleClient when provider is google' do
        stub_const('ENV', ENV.to_h.merge('GOOGLE_API_KEY' => 'key'))
        expect(described_class.build(config: { provider: 'google' })).to be_a(Commiti::GoogleClient)
      end

      it 'defaults to Google when provider key is absent' do
        stub_const('ENV', ENV.to_h.merge('GOOGLE_API_KEY' => 'key'))
        expect(described_class.build(config: {})).to be_a(Commiti::GoogleClient)
      end
    end

    context 'openai' do
      it 'returns OpenAIClient when OPENAI_API_KEY is set' do
        stub_const('ENV', ENV.to_h.merge('OPENAI_API_KEY' => 'sk-key'))
        expect(described_class.build(config: { provider: 'openai' })).to be_a(Commiti::OpenAIClient)
      end

      it 'raises ConfigError when OPENAI_API_KEY is missing' do
        stub_const('ENV', ENV.to_h.except('OPENAI_API_KEY'))
        expect { described_class.build(config: { provider: 'openai' }) }
          .to raise_error(Commiti::ConfigError, /OPENAI_API_KEY/)
      end
    end

    context 'anthropic' do
      it 'returns AnthropicClient when ANTHROPIC_API_KEY is set' do
        stub_const('ENV', ENV.to_h.merge('ANTHROPIC_API_KEY' => 'ant-key'))
        expect(described_class.build(config: { provider: 'anthropic' })).to be_a(Commiti::AnthropicClient)
      end

      it 'raises ConfigError when ANTHROPIC_API_KEY is missing' do
        stub_const('ENV', ENV.to_h.except('ANTHROPIC_API_KEY'))
        expect { described_class.build(config: { provider: 'anthropic' }) }
          .to raise_error(Commiti::ConfigError, /ANTHROPIC_API_KEY/)
      end
    end

    context 'ollama' do
      it 'returns OllamaClient without requiring a key' do
        expect(described_class.build(config: { provider: 'ollama' })).to be_a(Commiti::OllamaClient)
      end
    end

    context 'unknown provider' do
      it 'raises ConfigError' do
        expect { described_class.build(config: { provider: 'fakeprovider' }) }
          .to raise_error(Commiti::ConfigError, /Unknown provider/)
      end
    end
  end
end
