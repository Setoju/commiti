# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Commiti::PrCreator do
  describe '.create' do
    it 'returns missing token when provider token is not configured' do
      result = described_class.create(
        origin_url: 'git@github.com:acme/repo.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My PR',
        body: 'Body',
        config: {}
      )

      expect(result).to eq({ url: nil, reason: :missing_token, provider: :github })
    end

    it 'creates GitHub PR and returns html_url' do
      http = instance_double('Net::HTTP')
      response = instance_double('Net::HTTPResponse', code: '201', body: '{"html_url":"https://github.com/acme/repo/pull/42"}')

      allow(Net::HTTP).to receive(:start).with('github.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request) do |request|
        expect(request.path).to eq('/api/v3/repos/acme/repo/pulls')
        expect(request['Authorization']).to eq('token gh-token')
        expect(request['Content-Type']).to eq('application/json')

        payload = JSON.parse(request.body)
        expect(payload).to include(
          'title' => 'My PR',
          'head' => 'feat-x',
          'base' => 'main',
          'body' => 'Body'
        )

        response
      end

      result = described_class.create(
        origin_url: 'git@github.com:acme/repo.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My PR',
        body: 'Body',
        config: { github_token: 'gh-token' }
      )

      expect(result).to eq({ url: 'https://github.com/acme/repo/pull/42', reason: :created })
    end

    it 'creates GitLab MR and returns web_url' do
      http = instance_double('Net::HTTP')
      response = instance_double('Net::HTTPResponse', code: '201', body: '{"web_url":"https://gitlab.com/acme/repo/-/merge_requests/9"}')

      allow(Net::HTTP).to receive(:start).with('gitlab.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request) do |request|
        expect(request.path).to eq('/api/v4/projects/acme%2Frepo/merge_requests')
        expect(request['PRIVATE-TOKEN']).to eq('gl-token')
        expect(request['Content-Type']).to eq('application/json')

        payload = JSON.parse(request.body)
        expect(payload).to include(
          'title' => 'My MR',
          'source_branch' => 'feat-x',
          'target_branch' => 'main',
          'description' => 'Body'
        )

        response
      end

      result = described_class.create(
        origin_url: 'git@gitlab.com:acme/repo.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My MR',
        body: 'Body',
        config: { gitlab_token: 'gl-token' }
      )

      expect(result).to eq({ url: 'https://gitlab.com/acme/repo/-/merge_requests/9', reason: :created })
    end

    it 'returns api_error when provider API responds with an error' do
      http = instance_double('Net::HTTP')
      response = instance_double('Net::HTTPResponse', code: '422', body: '{"message":"Validation Failed"}')

      allow(Net::HTTP).to receive(:start).with('github.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).and_return(response)

      result = described_class.create(
        origin_url: 'git@github.com:acme/repo.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My PR',
        body: 'Body',
        config: { github_token: 'gh-token' }
      )

      expect(result[:url]).to be_nil
      expect(result[:reason]).to eq(:api_error)
      expect(result[:provider]).to eq(:github)
      expect(result[:error]).to include('HTTP 422')
    end
  end
end
