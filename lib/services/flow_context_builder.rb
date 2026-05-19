# frozen_string_literal: true

module Commiti
  module FlowContextBuilder
    def self.build(flow_type:, diff:, client:, run_stage:, model:)
      line_chunks = Commiti::DiffParser.split_by_file_lines(diff)
      diff_metadata = Commiti::DiffParser.metadata_from_line_chunks(line_chunks)
      change_groups = Commiti::ChangeGrouping.group(line_chunks)

      summarized_result = run_stage.call('Preparing diff for AI model') do
        Commiti::DiffSummarizer.summarize_if_needed(
          diff,
          client: client,
          model: model,
          chunks: summary_chunks(line_chunks)
        )
      end

      prompt = Commiti::PromptBuilder.build(
        type: flow_type,
        diff: summarized_result[:content],
        summarized: summarized_result[:summarized],
        raw_diff: diff,
        diff_metadata: diff_metadata
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
  end
end
