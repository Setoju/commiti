# frozen_string_literal: true

require_relative 'scope_inferrer'

module Commiti
  module FlowContextBuilder
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

      Commiti::ScopeInferrer.infer(
        files: Array(diff_metadata&.dig(:files)),
        common_scopes: style_profile.common_scopes
      )
    end
    private_class_method :infer_scope
  end
end
