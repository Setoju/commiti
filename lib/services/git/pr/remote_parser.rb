# frozen_string_literal: true

require 'uri'

module Commiti
  module PrRemoteParser
    SCP_REMOTE = %r{\A(?<user>[^@]+)@(?<host>[^:\s/]+):(?<path>[^\s]+)\z}

    def extract_remote_info(origin_url)
      remote_text = origin_url.to_s.strip
      return nil if remote_text.empty?

      parsed = parse_uri_remote(remote_text) || parse_scp_remote(remote_text)
      return nil if parsed.nil?

      normalized = normalize_repo_path(parsed[:path])
      return nil if normalized.nil?

      provider = detect_provider(parsed[:host])
      return nil if provider.nil?

      {
        provider: provider,
        host: parsed[:host],
        web_scheme: parsed[:web_scheme],
        namespace: normalized[:namespace],
        repo: normalized[:repo]
      }
    end

    private

    def parse_uri_remote(remote_text)
      uri = URI.parse(remote_text)
      return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS) || uri.scheme == 'ssh'
      return nil if uri.host.to_s.strip.empty?

      web_scheme = uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS) ? uri.scheme : 'https'
      { host: uri.host, path: uri.path, web_scheme: web_scheme }
    rescue URI::InvalidURIError
      nil
    end

    def parse_scp_remote(remote_text)
      match = remote_text.match(SCP_REMOTE)
      return nil if match.nil?

      { host: match[:host], path: match[:path], web_scheme: 'https' }
    end

    def normalize_repo_path(raw_path)
      clean = raw_path.to_s.strip
      clean = clean.sub(%r{\A/+}, '').sub(%r{/+\z}, '')
      clean = clean.sub(/\.git\z/, '')
      segments = clean.split('/').reject(&:empty?)
      return nil if segments.length < 2

      {
        namespace: segments[0..-2].join('/'),
        repo: segments[-1]
      }
    end

    def detect_provider(host)
      normalized = host.to_s.downcase
      return :gitlab if normalized.include?('gitlab')
      return :gitbucket if normalized.include?('gitbucket')
      return :github if normalized.include?('github')

      nil
    end
  end
end
