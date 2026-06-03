# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::OpenAIClient do
  let(:client) { described_class.new(config: {}) }
  let(:success_body) { { choices: [{ message: { content: 'feat: add user auth' } }] }.to_json }
  let(:ok_response) do
    instance_double(HTTParty::Response, success?: true, body: success_body,
                    parsed_response: JSON.parse(success_body))
  end

  describe '#generate' do
    it 'returns text from choices[0].message.content' do
      allow(described_class).to receive(:post).and_return(ok_response)
      expect(client.generate(system: 'sys', user: 'usr', model: 'gpt-4o')).to eq('feat: add user auth')
    end

    it 'sends system and user as chat messages' do
      allow(described_class).to receive(:post) do |_path, opts|
        body = JSON.parse(opts[:body])
        expect(body['messages']).to eq([
          { 'role' => 'system', 'content' => 'my system' },
          { 'role' => 'user', 'content' => 'my user' }
        ])
        ok_response
      end
      client.generate(system: 'my system', user: 'my user', model: 'gpt-4o')
    end

    it 'sets Authorization header with Bearer token' do
      stub_const('ENV', ENV.to_h.merge('OPENAI_API_KEY' => 'sk-abc'))
      allow(described_class).to receive(:post) do |_path, opts|
        expect(opts[:headers]['Authorization']).to eq('Bearer sk-abc')
        ok_response
      end
      client.generate(system: 's', user: 'u', model: 'gpt-4o')
    end

    it 'raises on non-2xx with error detail' do
      error_body = { error: { message: 'invalid api key' } }.to_json
      bad = instance_double(HTTParty::Response, success?: false, code: 401, body: error_body,
                            parsed_response: JSON.parse(error_body))
      allow(described_class).to receive(:post).and_return(bad)
      expect { client.generate(system: 's', user: 'u', model: 'm') }.to raise_error(/invalid api key/)
    end

    it 'raises when response content is empty' do
      empty_body = { choices: [{ message: { content: '' } }] }.to_json
      empty = instance_double(HTTParty::Response, success?: true, body: empty_body,
                              parsed_response: JSON.parse(empty_body))
      allow(described_class).to receive(:post).and_return(empty)
      expect { client.generate(system: 's', user: 'u', model: 'm') }
        .to raise_error(/OpenAI error: response did not include generated text/)
    end
  end
end
