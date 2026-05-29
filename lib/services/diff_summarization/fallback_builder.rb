# frozen_string_literal: true

module Commiti
  module DiffSummarizer
    module FallbackBuilder
      FALLBACK_BYTES = 12_000
      MAX_FILES_IN_SUMMARY = 40

      def self.mechanical_summary(diff)
        additions = diff.to_s.each_line.count { |line| line.start_with?('+') && !line.start_with?('+++') }
        deletions = diff.to_s.each_line.count { |line| line.start_with?('-') && !line.start_with?('---') }
        hunks = diff.to_s.each_line.count { |line| line.start_with?('@@') }
        "- #{additions} additions, #{deletions} deletions across #{hunks} hunk(s)"
      end

      def self.fallback_summary(diff, chunks: nil)
        parsed_chunks = chunks || Commiti::DiffParser.split_by_file(diff)
        files = file_stats_for(parsed_chunks)
        return diff.to_s[0, FALLBACK_BYTES] if files.empty?

        render_fallback_summary(files)
      end

      def self.file_stats_for(chunks)
        chunks.map { |chunk| file_stats_for_chunk(chunk) }
      end
      private_class_method :file_stats_for

      def self.file_stats_for_chunk(chunk)
        status, additions, deletions = file_status_and_counts(chunk[:diff])
        {
          path: chunk[:path].to_s,
          additions: additions,
          deletions: deletions,
          status: status
        }
      end
      private_class_method :file_stats_for_chunk

      def self.file_status_and_counts(diff_text)
        status = 'modified'
        additions = 0
        deletions = 0

        diff_text.to_s.each_line do |line|
          status = detect_status(line, current: status)
          next if metadata_line?(line)

          additions += 1 if line.start_with?('+')
          deletions += 1 if line.start_with?('-')
        end

        [status, additions, deletions]
      end
      private_class_method :file_status_and_counts

      def self.detect_status(line, current:)
        stripped = line.strip
        return 'added' if stripped.start_with?('new file mode')
        return 'deleted' if stripped.start_with?('deleted file mode')
        return 'renamed' if stripped.start_with?('rename from ') || stripped.start_with?('rename to ')

        current
      end
      private_class_method :detect_status

      def self.metadata_line?(line)
        line.start_with?('diff --git ', '+++', '---', '@@')
      end
      private_class_method :metadata_line?

      def self.render_fallback_summary(files)
        summary_lines = [
          '### Diff Overview',
          "- Total files changed: #{files.length}",
          ''
        ]

        append_file_sections(summary_lines, files)
        append_truncation_notice(summary_lines, files)

        summary_lines.join("\n").strip
      end
      private_class_method :render_fallback_summary

      def self.append_file_sections(summary_lines, files)
        files.first(MAX_FILES_IN_SUMMARY).each do |file|
          summary_lines.concat(render_file_section(file))
        end
      end
      private_class_method :append_file_sections

      def self.append_truncation_notice(summary_lines, files)
        summary_lines << "...and #{files.length - MAX_FILES_IN_SUMMARY} more files" if files.length > MAX_FILES_IN_SUMMARY
      end
      private_class_method :append_truncation_notice

      def self.render_file_section(file)
        [
          "### #{file[:path]}",
          "- Status: #{file[:status]}",
          "- Added lines: #{file[:additions]}",
          "- Removed lines: #{file[:deletions]}",
          ''
        ]
      end
      private_class_method :render_file_section
    end
  end
end
