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

      allow(Net::HTTP).to receive(:start).with('api.github.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request) do |request|
        expect(request.path).to eq('/repos/acme/repo/pulls')
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

      allow(Net::HTTP).to receive(:start).with('api.github.com', 443, use_ssl: true).and_yield(http)
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

    it 'creates GitBucket PR and returns html_url' do
      http = instance_double('Net::HTTP')
      response = instance_double('Net::HTTPResponse', code: '201', body: '{"html_url":"https://gitbucket.example.com/acme/repo/pull/7"}')

      allow(Net::HTTP).to receive(:start).with('gitbucket.example.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request) do |request|
        # GitBucket is not github.com, so it uses GitHub Enterprise style endpoint
        expect(request.path).to eq('/api/v3/repos/acme/repo/pulls')
        expect(request['Authorization']).to eq('token gb-token')

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
        origin_url: 'https://gitbucket.example.com/acme/repo.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My PR',
        body: 'Body',
        config: { gitbucket_token: 'gb-token' }
      )

      expect(result).to eq({ url: 'https://gitbucket.example.com/acme/repo/pull/7', reason: :created })
    end

    it 'uses GitHub Enterprise API endpoint when host is not github.com' do
      http = instance_double('Net::HTTP')
      response = instance_double('Net::HTTPResponse', code: '201', body: '{"html_url":"https://github.enterprise.com/acme/repo/pull/5"}')

      allow(Net::HTTP).to receive(:start).with('github.enterprise.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request) do |request|
        expect(request.path).to eq('/api/v3/repos/acme/repo/pulls')
        expect(request['Authorization']).to eq('token gh-ent-token')

        response
      end

      result = described_class.create(
        origin_url: 'git@github.enterprise.com:acme/repo.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My PR',
        body: 'Body',
        config: { github_token: 'gh-ent-token' }
      )

      expect(result).to eq({ url: 'https://github.enterprise.com/acme/repo/pull/5', reason: :created })
    end

    it 'returns api_error when status code is 3xx without redirect location header' do
      http = instance_double('Net::HTTP')
      redirect_response = instance_double('Net::HTTPResponse', code: '302', body: '')

      allow(Net::HTTP).to receive(:start).with('api.github.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).and_return(redirect_response)
      allow(redirect_response).to receive(:[]).with('Location').and_return('')

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
      expect(result[:error]).to include('Redirect')
    end

    it 'returns api_error when redirected to different host' do
      http = instance_double('Net::HTTP')
      redirect_response = instance_double('Net::HTTPResponse', code: '302', body: '')

      allow(Net::HTTP).to receive(:start).with('api.github.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).and_return(redirect_response)
      allow(redirect_response).to receive(:[]).with('Location').and_return('https://attacker.com/phishing')

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
      expect(result[:error]).to include('different host')
    end

    it 'returns api_error when response is missing html_url' do
      http = instance_double('Net::HTTP')
      response = instance_double('Net::HTTPResponse', code: '201', body: '{"state":"open"}')

      allow(Net::HTTP).to receive(:start).with('api.github.com', 443, use_ssl: true).and_yield(http)
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
      expect(result[:error]).to include('html_url')
    end

    it 'returns unsupported_provider for unsupported origin' do
      result = described_class.create(
        origin_url: 'git@bitbucket.org:acme/repo.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My PR',
        body: 'Body',
        config: { bitbucket_token: 'token' }
      )

      expect(result).to eq({ url: nil, reason: :unsupported_provider })
    end

    it 'returns api_error with GitLab error details array' do
      http = instance_double('Net::HTTP')
      error_response = instance_double('Net::HTTPResponse', code: '422', body: '{"message":"Validation Failed","errors":[{"field":"source_branch","code":"taken","message":"has already been taken"}]}')

      allow(Net::HTTP).to receive(:start).with('gitlab.com', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:request).and_return(error_response)

      result = described_class.create(
        origin_url: 'git@gitlab.com:acme/repo.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My MR',
        body: 'Body',
        config: { gitlab_token: 'gl-token' }
      )

      expect(result[:url]).to be_nil
      expect(result[:reason]).to eq(:api_error)
      expect(result[:error]).to include('Validation Failed')
      expect(result[:error]).to include('source_branch: taken: has already been taken')
    end

    it 'handles invalid JSON response gracefully' do
      http = instance_double('Net::HTTP')
      response = instance_double('Net::HTTPResponse', code: '500', body: 'Internal Server Error')

      allow(Net::HTTP).to receive(:start).with('api.github.com', 443, use_ssl: true).and_yield(http)
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
      expect(result[:error]).to include('HTTP 500')
      expect(result[:error]).to include('Internal Server Error')
    end

    it 'catches StandardError from network issues' do
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'Connection refused')

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
      expect(result[:error]).to include('Connection refused')
    end
  end
end
