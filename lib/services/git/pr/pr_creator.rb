# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative 'remote_parser'

module Commiti
  module PrCreator
    extend PrRemoteParser

    def self.create(origin_url:, base_branch:, head_branch:, title:, body:, config:)
      remote = extract_remote_info(origin_url)
      return { url: nil, reason: :unsupported_provider } if remote.nil?

      token = token_for_provider(remote[:provider], config)
      return { url: nil, reason: :missing_token, provider: remote[:provider] } if token.nil?

      url = case remote[:provider]
            when :github, :gitbucket
              create_github_like_pr(remote: remote, base_branch: base_branch, head_branch: head_branch,
                                    title: title, body: body, token: token)
            when :gitlab
              create_gitlab_mr(remote: remote, base_branch: base_branch, head_branch: head_branch,
                               title: title, body: body, token: token)
            end

      return { url: nil, reason: :unsupported_provider } if url.nil?

      { url: url, reason: :created }
    rescue StandardError => e
      { url: nil, reason: :api_error, provider: remote && remote[:provider], error: e.message }
    end

    def self.create_github_like_pr(remote:, base_branch:, head_branch:, title:, body:, token:)
      uri = github_api_uri(remote, "/repos/#{remote[:namespace]}/#{remote[:repo]}/pulls")
      payload = {
        title: title.to_s,
        head: head_branch.to_s,
        base: base_branch.to_s,
        body: body.to_s
      }

      response = post_json(
        uri,
        payload,
        {
          'Authorization' => "token #{token}",
          'Accept' => 'application/vnd.github+json'
        }
      )

      parsed = parse_json(response)
      url = parsed['html_url']
      raise 'PR API response did not include html_url.' if url.to_s.strip.empty?

      url
    end
    private_class_method :create_github_like_pr

    # github.com uses api.github.com; GitHub Enterprise uses /api/v3 on the same host.
    def self.github_api_uri(remote, path)
      base = if remote[:host].to_s.downcase == 'github.com'
               'https://api.github.com'
             else
               "#{remote[:web_scheme]}://#{remote[:host]}/api/v3"
             end

      URI("#{base}#{path}")
    end
    private_class_method :github_api_uri

    def self.create_gitlab_mr(remote:, base_branch:, head_branch:, title:, body:, token:)
      encoded_project = URI.encode_www_form_component("#{remote[:namespace]}/#{remote[:repo]}")
      uri = URI("#{remote_base(remote)}/api/v4/projects/#{encoded_project}/merge_requests")
      payload = {
        source_branch: head_branch.to_s,
        target_branch: base_branch.to_s,
        title: title.to_s,
        description: body.to_s
      }

      response = post_json(
        uri,
        payload,
        {
          'PRIVATE-TOKEN' => token,
          'Accept' => 'application/json'
        }
      )

      parsed = parse_json(response)
      url = parsed['web_url']
      raise 'MR API response did not include web_url.' if url.to_s.strip.empty?

      url
    end
    private_class_method :create_gitlab_mr

    def self.post_json(uri, payload, headers, redirect_limit: 5)
      raise 'Too many redirects' if redirect_limit.zero?

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      headers.each { |k, v| request[k] = v }
      request.body = JSON.generate(payload)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        response = http.request(request)
        code = response.code.to_i

        if [301, 302, 307, 308].include?(code)
          location = response['Location'].to_s.strip
          raise 'Redirect with no Location header' if location.empty?

          new_uri = URI(location)
          new_uri = URI("#{uri.scheme}://#{uri.host}#{location}") unless new_uri.host

          # Never follow to a different host — that means the API pushed us to the web UI
          raise "API redirected to a different host (#{new_uri.host}), check namespace/repo in origin URL" \
            if new_uri.host != uri.host

          return post_json(new_uri, payload, headers, redirect_limit: redirect_limit - 1)
        end

        return response if code.between?(200, 299)

        parsed = parse_json(response)
        errors = parsed['errors']&.map { |e| e.slice('field', 'code', 'message').values.join(': ') }&.join(', ')
        base_msg = parsed['message'] || parsed['error'] || response.body.to_s.strip
        detail = errors ? "#{base_msg} — #{errors}" : base_msg
        raise "PR API request failed (HTTP #{code}): #{detail}"
      end
    end
    private_class_method :post_json

    def self.parse_json(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end
    private_class_method :parse_json

    def self.remote_base(remote)
      "#{remote[:web_scheme]}://#{remote[:host]}"
    end
    private_class_method :remote_base

    def self.token_for_provider(provider, config)
      case provider
      when :github
        present_or_nil(config[:github_token])
      when :gitlab
        present_or_nil(config[:gitlab_token])
      when :gitbucket
        present_or_nil(config[:gitbucket_token])
      end
    end
    private_class_method :token_for_provider

    def self.present_or_nil(value)
      normalized = value.to_s.strip
      normalized.empty? ? nil : normalized
    end
    private_class_method :present_or_nil
  end
end
