# frozen_string_literal: true

module Commiti
  module ScopeInferrer
    FALLBACK_SCOPE_MAP = {
      'auth' => 'auth',
      'authentication' => 'auth',
      'sessions' => 'auth',
      'api' => 'api',
      'controllers' => 'api',
      'models' => 'db',
      'db' => 'db',
      'migrations' => 'db',
      'spec' => 'test',
      'test' => 'test',
      'config' => 'config'
    }.freeze

    def self.infer(files:, common_scopes:)
      return nil if files.nil? || files.empty?

      normalized_common = Array(common_scopes).map { |scope| scope.to_s.strip.downcase }.reject(&:empty?)
      inferred = Array(files).filter_map do |file|
        segments = file.to_s.split('/').reject(&:empty?)
        next if segments.empty?

        match = match_common_scope(segments, normalized_common)
        match || fallback_scope(segments)
      end

      inferred = inferred.compact.uniq
      return nil if inferred.empty?
      return inferred.first if inferred.length == 1

      nil
    rescue StandardError
      nil
    end

    def self.match_common_scope(segments, common_scopes)
      return nil if common_scopes.empty?

      segments.each do |segment|
        normalized = segment.to_s.downcase
        return normalized if common_scopes.include?(normalized)
      end
      nil
    end
    private_class_method :match_common_scope

    def self.fallback_scope(segments)
      segments.each_with_index do |segment, index|
        normalized = segment.to_s.downcase
        return FALLBACK_SCOPE_MAP[normalized] if FALLBACK_SCOPE_MAP.key?(normalized)

        next unless normalized == 'lib'

        next_segment = segments[index + 1].to_s
        return nil if next_segment.empty?

        base = File.basename(next_segment, File.extname(next_segment)).downcase
        return FALLBACK_SCOPE_MAP.fetch(base, base)
      end
      nil
    end
    private_class_method :fallback_scope
  end
end
