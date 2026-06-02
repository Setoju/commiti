# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::OllamaClient do
  let(:client) { described_class.new(config: {}) }
  let(:success_body) { { message: { content: 'feat: cache results' } }.to_json }
  let(:ok_response) do
    instance_double(HTTParty::Response, success?: true, body: success_body,
                    parsed_response: JSON.parse(success_body))
  end

  before { stub_const('ENV', ENV.to_h.merge('OLLAMA_BASE_URL' => 'http://localhost:11434')) }

  describe '#generate' do
    it 'returns text from message.content' do
      allow(described_class).to receive(:post).and_return(ok_response)
      expect(client.generate(system: 'sys', user: 'usr', model: 'llama3.2')).to eq('feat: cache results')
    end

    it 'sends stream: false' do
      allow(described_class).to receive(:post) do |_url, opts|
        expect(JSON.parse(opts[:body])['stream']).to be(false)
        ok_response
      end
      client.generate(system: 's', user: 'u', model: 'llama3.2')
    end

    it 'posts to OLLAMA_BASE_URL/api/chat' do
      allow(described_class).to receive(:post) do |url, _opts|
        expect(url).to eq('http://localhost:11434/api/chat')
        ok_response
      end
      client.generate(system: 's', user: 'u', model: 'llama3.2')
    end

    it 'raises on non-2xx' do
      bad = instance_double(HTTParty::Response, success?: false, code: 500,
                            body: 'internal error', parsed_response: 'internal error')
      allow(described_class).to receive(:post).and_return(bad)
      expect { client.generate(system: 's', user: 'u', model: 'm') }.to raise_error(/Ollama error: 500/)
    end
  end
end
