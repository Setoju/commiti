# frozen_string_literal: true

module Commiti
  module FlowContextBuilder
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

    def self.build(flow_type:, diff:, client:, run_stage:, model:, text_generation_config: nil, worker_count: nil,
                   style_profile: nil, inferred_scope: nil)
      line_chunks = Commiti::DiffParser.split_by_file_lines(diff)
      diff_metadata = Commiti::DiffParser.metadata_from_line_chunks(line_chunks)
      change_groups = Commiti::ChangeGrouping.group(line_chunks)
      inferred_scope ||= infer_scope(flow_type, diff_metadata, style_profile)

      summarized_result = run_stage.call('Preparing diff for AI model') do
        Commiti::DiffSummarizer.summarize_if_needed(
          diff,
          client: client,
          model: model,
          chunks: summary_chunks(line_chunks),
          worker_count: worker_count
        )
      end

      prompt = Commiti::PromptBuilder.build(
        type: flow_type,
        diff: summarized_result[:content],
        summarized: summarized_result[:summarized],
        raw_diff: diff,
        diff_metadata: diff_metadata,
        style_config: text_generation_config,
        style_profile: style_profile,
        inferred_scope: inferred_scope
      )

      {
        diff_metadata: diff_metadata,
        change_groups: change_groups,
        summarized_result: summarized_result,
        prompt: prompt
      }
    end

    def self.summary_chunks(line_chunks)
      line_chunks.map { |chunk| { path: chunk[:path], diff: chunk[:lines].join } }
    end
    private_class_method :summary_chunks

    def self.infer_scope(flow_type, diff_metadata, style_profile)
      return nil unless flow_type == :commit
      return nil unless style_profile

      infer_scope_for_files(
        files: Array(diff_metadata&.dig(:files)),
        common_scopes: style_profile.common_scopes
      )
    end
    private_class_method :infer_scope

    def self.infer_scope_for_files(files:, common_scopes:)
      return nil if files.nil? || files.empty?

      normalized_common = Array(common_scopes).map { |scope| scope.to_s.strip.downcase }.reject(&:empty?)
      inferred = Array(files).filter_map do |file|
        segments = file.to_s.split('/').reject(&:empty?)
        next if segments.empty?

        match_common_scope(segments, normalized_common) || fallback_scope(segments)
      end

      inferred = inferred.compact.uniq
      return nil if inferred.empty?
      return inferred.first if inferred.length == 1

      nil
    rescue StandardError
      nil
    end
    private_class_method :infer_scope_for_files

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
