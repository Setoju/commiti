# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::AnthropicClient do
  let(:client) { described_class.new(config: {}) }
  let(:success_body) { { content: [{ text: 'feat: improve error messages' }] }.to_json }
  let(:ok_response) do
    instance_double(HTTParty::Response, success?: true, body: success_body,
                    parsed_response: JSON.parse(success_body))
  end

  describe '#generate' do
    it 'returns text from content[0].text' do
      allow(described_class).to receive(:post).and_return(ok_response)
      expect(client.generate(system: 'sys', user: 'usr', model: 'claude-sonnet-4-6'))
        .to eq('feat: improve error messages')
    end

    it 'sends system as top-level field and user as messages array' do
      allow(described_class).to receive(:post) do |_path, opts|
        body = JSON.parse(opts[:body])
        expect(body['system']).to eq('my system')
        expect(body['messages']).to eq([{ 'role' => 'user', 'content' => 'my user' }])
        ok_response
      end
      client.generate(system: 'my system', user: 'my user', model: 'claude-sonnet-4-6')
    end

    it 'sends anthropic-version header' do
      allow(described_class).to receive(:post) do |_path, opts|
        expect(opts[:headers]['anthropic-version']).to eq('2023-06-01')
        ok_response
      end
      client.generate(system: 's', user: 'u', model: 'm')
    end

    it 'raises on non-2xx with error detail' do
      error_body = { error: { message: 'permission denied' } }.to_json
      bad = instance_double(HTTParty::Response, success?: false, code: 403, body: error_body,
                            parsed_response: JSON.parse(error_body))
      allow(described_class).to receive(:post).and_return(bad)
      expect { client.generate(system: 's', user: 'u', model: 'm') }.to raise_error(/permission denied/)
    end
  end
end
