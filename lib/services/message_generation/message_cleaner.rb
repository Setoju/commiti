# frozen_string_literal: true

module Commiti
  module MessageCleaner
    private

    def clean_output(text)
      lines = text.to_s.strip.lines
      index = if flow_type == :pr
                headers = Commiti::TextGenerationStyle.pr_section_headers(text_generation_config)
                lines.index { |line| headers.include?(line.strip) }
              else
                lines.index { |line| line.match?(/\A(feat|fix|chore|refactor|docs|style|test|perf|ci|build|revert)[(!:]/i) }
              end
      index ? lines[index..].join.strip : text.to_s.strip
    end
  end
end
