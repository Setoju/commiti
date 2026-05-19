# frozen_string_literal: true

require 'spec_helper'
require 'cgi'
require 'uri'

RSpec.describe Commiti::PrOpener do
  describe '.compare_url' do
    it 'builds a GitHub compare URL from SSH origin' do
      url = described_class.compare_url(
        origin_url: 'git@github.com:acme/commiti.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My PR',
        body: 'Body text'
      )

      expect(url).to start_with('https://github.com/acme/commiti/compare/main...feat-x?')

      query = CGI.parse(URI.parse(url).query)
      expect(query['quick_pull']).to eq(['1'])
      expect(query['title']).to eq(['My PR'])
      expect(query['body']).to eq(['Body text'])
    end

    it 'builds a GitLab merge request URL from SSH origin' do
      url = described_class.compare_url(
        origin_url: 'git@gitlab.com:acme/subgroup/commiti.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My MR',
        body: 'MR body'
      )

      expect(url).to start_with('https://gitlab.com/acme/subgroup/commiti/-/merge_requests/new?')

      query = CGI.parse(URI.parse(url).query)
      expect(query['merge_request[source_branch]']).to eq(['feat-x'])
      expect(query['merge_request[target_branch]']).to eq(['main'])
      expect(query['merge_request[title]']).to eq(['My MR'])
      expect(query['merge_request[description]']).to eq(['MR body'])
    end

    it 'omits GitHub body prefill when URL would be too long' do
      url = described_class.compare_url(
        origin_url: 'git@github.com:acme/commiti.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My PR',
        body: 'x' * 6_000
      )

      query = CGI.parse(URI.parse(url).query)
      expect(query['title']).to eq(['My PR'])
      expect(query).not_to have_key('body')
      expect(url.length).to be <= described_class::MAX_PREFILLED_URL_LENGTH
    end

    it 'omits GitLab description prefill when URL would be too long' do
      url = described_class.compare_url(
        origin_url: 'git@gitlab.com:acme/subgroup/commiti.git',
        base_branch: 'main',
        head_branch: 'feat-x',
        title: 'My MR',
        body: 'x' * 6_000
      )

      query = CGI.parse(URI.parse(url).query)
      expect(query['merge_request[title]']).to eq(['My MR'])
      expect(query).not_to have_key('merge_request[description]')
      expect(url.length).to be <= described_class::MAX_PREFILLED_URL_LENGTH
    end

    it 'builds a GitBucket compare URL from HTTPS origin' do
      url = described_class.compare_url(
        origin_url: 'https://gitbucket.example.com/acme/commiti.git',
        base_branch: 'main',
        head_branch: 'feat/with-slash',
        title: 'My PR',
        body: 'Body text'
      )

      expect(url).to start_with('https://gitbucket.example.com/acme/commiti/compare/main...feat%2Fwith-slash?')

      query = CGI.parse(URI.parse(url).query)
      expect(query['expand']).to eq(['1'])
      expect(query['title']).to eq(['My PR'])
      expect(query['body']).to eq(['Body text'])
    end

    it 'raises when remote provider is unsupported' do
      expect do
        described_class.compare_url(
          origin_url: 'git@bitbucket.org:group/project.git',
          base_branch: 'main',
          head_branch: 'feat-x',
          title: 'PR',
          body: 'Body'
        )
      end.to raise_error('Supported providers for browser PR opening are GitHub, GitLab, and GitBucket.')
    end
  end

  describe '.suggest_title' do
    it 'extracts title from summary section' do
      pr_body = <<~BODY
        ## Summary
        Add API key caching

        ## Motivation
        Avoid repeated network calls.
      BODY

      expect(described_class.suggest_title(pr_body, head_branch: 'feature/cache')).to eq('Add API key caching')
    end

    it 'falls back to branch name when summary has no prose line' do
      pr_body = <<~BODY
        ## Summary
        - Bullet only

        ## Motivation
        Some reason
      BODY

      expect(described_class.suggest_title(pr_body, head_branch: 'feature/cache')).to eq('Update feature/cache')
    end
  end

  describe '.extract_owner_repo' do
    it 'parses HTTPS and SSH URL formats' do
      expect(described_class.extract_owner_repo('https://github.com/acme/repo.git')).to eq({ owner: 'acme',
                                                                                             repo: 'repo' })
      expect(described_class.extract_owner_repo('ssh://git@github.com/acme/repo.git')).to eq({ owner: 'acme',
                                                                                               repo: 'repo' })
    end

    it 'keeps nested namespaces for GitLab remotes' do
      expect(described_class.extract_owner_repo('git@gitlab.com:acme/subgroup/repo.git')).to eq({
                                                                                                  owner: 'acme/subgroup',
                                                                                                  repo: 'repo'
                                                                                                })
    end
  end
end
