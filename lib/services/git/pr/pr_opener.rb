# frozen_string_literal: true

require 'uri'
require_relative 'remote_parser'
require_relative 'browser_opener'

module Commiti
  module PrOpener
    SCP_REMOTE = %r{\A(?<user>[^@]+)@(?<host>[^:\s/]+):(?<path>[^\s]+)\z}
    MAX_PREFILLED_URL_LENGTH = 1800
    MAX_PREFILLED_TITLE_LENGTH = 120

    extend PrRemoteParser

    def self.compare_url(origin_url:, base_branch:, head_branch:, title:, body:)
      remote = extract_remote_info(origin_url)
      raise 'Supported providers for browser PR opening are GitHub, GitLab, and GitBucket.' if remote.nil?

      compare_url_candidates(
        remote: remote,
        base_branch: base_branch,
        head_branch: head_branch,
        title: title,
        body: body
      ).find { |url| url.length <= MAX_PREFILLED_URL_LENGTH } || compare_url_candidates(
        remote: remote,
        base_branch: base_branch,
        head_branch: head_branch,
        title: title,
        body: body
      ).last
    end

    def self.compare_url_candidates(remote:, base_branch:, head_branch:, title:, body:)
      truncated_body = truncate_body_to_fit(
        remote: remote,
        base_branch: base_branch,
        head_branch: head_branch,
        title: title,
        body: body
      )

      [
        prefilled_url(
          remote: remote,
          base_branch: base_branch,
          head_branch: head_branch,
          title: title,
          body: body,
          include_title: true,
          include_body: true
        ),
        prefilled_url(
          remote: remote,
          base_branch: base_branch,
          head_branch: head_branch,
          title: title,
          body: truncated_body,
          include_title: true,
          include_body: !truncated_body.to_s.empty?
        ),
        prefilled_url(
          remote: remote,
          base_branch: base_branch,
          head_branch: head_branch,
          title: title,
          body: body,
          include_title: true,
          include_body: false
        ),
        prefilled_url(
          remote: remote,
          base_branch: base_branch,
          head_branch: head_branch,
          title: title,
          body: body,
          include_title: false,
          include_body: false
        )
      ]
    end
    private_class_method :compare_url_candidates

    def self.truncate_body_to_fit(remote:, base_branch:, head_branch:, title:, body:)
      text = body.to_s
      return '' if text.empty?

      full_url = prefilled_url(
        remote: remote,
        base_branch: base_branch,
        head_branch: head_branch,
        title: title,
        body: text,
        include_title: true,
        include_body: true
      )
      return text if full_url.length <= MAX_PREFILLED_URL_LENGTH

      low = 0
      high = text.length
      best = ''

      while low <= high
        mid = (low + high) / 2
        candidate_body = text[0, mid]
        candidate_url = prefilled_url(
          remote: remote,
          base_branch: base_branch,
          head_branch: head_branch,
          title: title,
          body: candidate_body,
          include_title: true,
          include_body: !candidate_body.empty?
        )

        if candidate_url.length <= MAX_PREFILLED_URL_LENGTH
          best = candidate_body
          low = mid + 1
        else
          high = mid - 1
        end
      end

      best
    end
    private_class_method :truncate_body_to_fit

    def self.prefilled_url(remote:, base_branch:, head_branch:, title:, body:, include_title:, include_body:)
      if remote[:provider] == :gitlab
        gitlab_mr_url(
          remote: remote,
          base_branch: base_branch,
          head_branch: head_branch,
          title: title,
          body: body,
          include_title: include_title,
          include_description: include_body
        )
      else
        github_like_compare_url(
          remote: remote,
          base_branch: base_branch,
          head_branch: head_branch,
          title: title,
          body: body,
          include_title: include_title,
          include_body: include_body
        )
      end
    end
    private_class_method :prefilled_url

    def self.github_like_compare_url(remote:, base_branch:, head_branch:, title:, body:, include_title: true, include_body: true)
      query_params = {
        github_compare_prefill_param(remote[:provider]) => '1'
      }
      normalized_title = normalize_title(title)
      query_params['title'] = normalized_title if include_title && !normalized_title.empty?
      query_params['body'] = body.to_s if include_body && !body.to_s.empty?
      query = URI.encode_www_form(query_params)

      base = "#{remote[:web_scheme]}://#{remote[:host]}"
      path = "#{remote[:namespace]}/#{remote[:repo]}"

      "#{base}/#{path}/compare/#{encode_branch_for_path(base_branch)}...#{encode_branch_for_path(head_branch)}?#{query}"
    end

    def self.github_compare_prefill_param(provider)
      provider == :github ? 'quick_pull' : 'expand'
    end
    private_class_method :github_compare_prefill_param

    def self.gitlab_mr_url(remote:, base_branch:, head_branch:, title:, body:, include_title: true, include_description: true)
      query_params = {
        'merge_request[source_branch]' => head_branch,
        'merge_request[target_branch]' => base_branch
      }
      normalized_title = normalize_title(title)
      query_params['merge_request[title]'] = normalized_title if include_title && !normalized_title.empty?
      query_params['merge_request[description]'] = body.to_s if include_description && !body.to_s.empty?
      query = URI.encode_www_form(query_params)

      base = "#{remote[:web_scheme]}://#{remote[:host]}"
      path = "#{remote[:namespace]}/#{remote[:repo]}"

      "#{base}/#{path}/-/merge_requests/new?#{query}"
    end

    def self.normalize_title(title)
      title.to_s.strip[0, MAX_PREFILLED_TITLE_LENGTH]
    end
    private_class_method :normalize_title

    def self.encode_branch_for_path(branch)
      URI.encode_www_form_component(branch.to_s).gsub('+', '%20')
    end

    def self.suggest_title(pr_body, head_branch:)
      in_summary = false
      pr_body.to_s.each_line do |line|
        stripped = line.strip
        if stripped == '## Summary'
          in_summary = true
          next
        end

        break if in_summary && stripped.start_with?('## ')
        next unless in_summary
        next if stripped.empty? || stripped.start_with?('-', '*')

        return stripped[0, 72]
      end

      "Update #{head_branch}"
    end

    def self.open_in_browser(url)
      Commiti::PrBrowserOpener.open_in_browser(url)
    end

    def self.extract_owner_repo(origin_url)
      info = extract_remote_info(origin_url)
      return nil if info.nil?

      { owner: info[:namespace], repo: info[:repo] }
    end
  end
end
