# frozen_string_literal: true

module Commiti
  module CommitNormalizer
    private

    def normalize_commit_message(message, diff_metadata:)
      first_line = message.to_s.strip.lines.first.to_s.strip
      return nil if first_line.empty?

      source_subject = cleaned_commit_subject(message)
      source_subject = Commiti::MessageGenerator::DEFAULT_COMMIT_SUBJECT if source_subject.empty?

      prefix = extracted_commit_prefix(first_line) || inferred_commit_prefix(source_subject, diff_metadata: diff_metadata)
      max_subject_length = Commiti::InteractivePrompt::COMMIT_SUBJECT_MAX_LENGTH - "#{prefix}: ".length
      subject = Commiti::TextGenerationStyle.apply_commit_subject_case(source_subject, text_generation_config)
      subject = subject[0, max_subject_length].to_s.rstrip
      subject = Commiti::MessageGenerator::DEFAULT_COMMIT_SUBJECT[0, max_subject_length] if subject.empty?

      normalized = "#{prefix}: #{subject}"
      return nil unless Commiti::InteractivePrompt.commit_message_errors(normalized).empty?

      normalized
    end

    def extracted_commit_prefix(first_line)
      match = first_line.match(/\A(?<prefix>(?:feat|fix|chore|refactor|docs|style|test|perf|ci|build|revert)(?:\([^)]+\))?!?)\s*:/i)
      match&.[](:prefix)&.downcase
    end

    def cleaned_commit_subject(message)
      first_line = message.to_s.lines.map(&:strip).find { |line| !line.empty? }.to_s
      first_line = first_line.sub(/\A(?:commit\s+message|subject)\s*:\s*/i, '')
      first_line = first_line.sub(/\A[`"'*#>\-\d.)\s]+/, '')
      first_line = first_line.sub(Commiti::MessageGenerator::COMMIT_PREFIX_PATTERN, '')
      first_line.strip
    end

    def inferred_commit_prefix(subject, diff_metadata:)
      return 'docs' if diff_metadata[:docs_only]

      lowered = subject.to_s.downcase
      return 'fix' if lowered.match?(/\b(fix|bug|error|issue|crash|regress|correct|resolve)\b/)
      return 'test' if lowered.match?(/\b(test|spec)\b/)
      return 'refactor' if lowered.match?(/\b(refactor|cleanup|reorganize|restructure)\b/)
      return 'perf' if lowered.match?(/\b(perf|performance|optimi[sz]e)\b/)
      return 'ci' if lowered.match?(/\b(ci|workflow|pipeline)\b/)
      return 'build' if lowered.match?(/\b(build|dependency|deps|gemfile|package)\b/)

      'feat'
    end
  end
end
