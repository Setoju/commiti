# frozen_string_literal: true

require_relative 'message_generator_support'

module Commiti
  class MessageGenerator
    include MessageGeneratorSupport

    COMMIT_PREFIX_ERROR = 'First line must start with a conventional commit type (feat:, fix:, etc.).'
    DEFAULT_COMMIT_SUBJECT = 'update project files'
    COMMIT_PREFIX_PATTERN = /\A(feat|fix|chore|refactor|docs|style|test|perf|ci|build|revert)(\([^)]+\))?!?\s*:?\s*/i

    def initialize(flow_type:, run_stage:, text_generation_config: nil)
      @flow_type = flow_type
      @run_stage = run_stage
      @text_generation_config = text_generation_config || Commiti::TextGenerationStyle::DEFAULT_CONFIG
    end

    def generate_candidates(client:, prompt:, diff_metadata:, count:, model:)
      (1..count).map do |index|
        puts "\nGenerating candidate #{index}/#{count}..."
        generate_with_quality_check(client: client, prompt: prompt, diff_metadata: diff_metadata, model: model)
      end
    end

    def generate_with_quality_check(client:, prompt:, diff_metadata:, model:)
      message = clean_output(generate_from_client(
                               client: client,
                               system: prompt[:system],
                               user: prompt[:user],
                               model: model,
                               label: "Generating #{flow_type} with Google AI"
                             ))
      reason = invalid_generation_reason(message: message, diff_metadata: diff_metadata)
      return normalize_commit_message(message, diff_metadata: diff_metadata) if reason.nil? && flow_type == :commit
      return message if reason.nil?

      puts "\nGenerated output looked weak: #{reason}"
      puts "Retrying once with stronger constraints...\n"

      retried_message = clean_output(generate_from_client(
                                       client: client,
                                       system: prompt[:system],
                                       user: retry_prompt(prompt:, reason: reason),
                                       model: model,
                                       label: "Regenerating #{flow_type} with stricter prompt"
                                     ))
      retry_reason = invalid_generation_reason(message: retried_message, diff_metadata: diff_metadata)
      if flow_type == :commit && retry_reason&.include?(COMMIT_PREFIX_ERROR)
        normalized_commit = normalize_commit_message(retried_message, diff_metadata: diff_metadata)
        return normalized_commit || retried_message
      end
      return normalize_commit_message(retried_message, diff_metadata: diff_metadata) if retry_reason.nil? && flow_type == :commit
      return retried_message if retry_reason.nil?

      raise "Generated #{flow_type} is still invalid after retry: #{retry_reason}"
    end

    private

    attr_reader :flow_type, :run_stage, :text_generation_config

    def generate_from_client(client:, system:, user:, model:, label:)
      run_stage.call(label) do
        client.generate(
          system: system,
          user: user,
          model: model,
          timeout_seconds: 300,
          open_timeout_seconds: 10
        )
      end
    end

    def retry_prompt(prompt:, reason:)
      <<~MSG
        #{prompt[:user].rstrip}

        Your previous draft was invalid: #{reason}
        Rewrite from scratch using only the provided diff content.
        Do not claim there were no changes if files were changed.
      MSG
    end
  end
end
