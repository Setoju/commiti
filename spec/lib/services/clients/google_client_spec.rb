# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::GoogleClient do
  describe '#generate' do
    let(:client) { described_class.new(config: { google_api_key: 'test-key' }) }
    let(:success_body) do
      { candidates: [{ content: { parts: [{ text: 'feat: add login' }] } }] }.to_json
    end
    let(:ok_response) do
      instance_double(HTTParty::Response, success?: true, body: success_body)
    end

    it 'returns extracted text on success' do
      allow(described_class).to receive(:post).and_return(ok_response)
      expect(client.generate(system: 'sys', user: 'usr', model: 'gemma-4-31b-it')).to eq('feat: add login')
    end

    it 'raises when API key is missing' do
      bare = described_class.new(config: {})
      allow(described_class).to receive(:post).and_return(ok_response)
      expect { bare.generate(system: 's', user: 'u', model: 'gemma-4-31b-it') }
        .to raise_error(/Google API key is missing/)
    end

    it 'raises with error detail on non-2xx response' do
      error_body = { error: { message: 'quota exceeded' } }.to_json
      bad = instance_double(HTTParty::Response, success?: false, code: 429, body: error_body)
      allow(described_class).to receive(:post).and_return(bad)
      expect { client.generate(system: 's', user: 'u', model: 'm') }
        .to raise_error(/quota exceeded/)
    end
  end
end
