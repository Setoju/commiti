# frozen_string_literal: true

module Commiti
  module DiffSummarizer
    module FallbackBuilder
      def mechanical_summary(diff)
        additions = diff.to_s.each_line.count { |line| line.start_with?('+') && !line.start_with?('+++') }
        deletions = diff.to_s.each_line.count { |line| line.start_with?('-') && !line.start_with?('---') }
        hunks = diff.to_s.each_line.count { |line| line.start_with?('@@') }
        "- #{additions} additions, #{deletions} deletions across #{hunks} hunk(s)"
      end

      def fallback_summary(diff, chunks: nil)
        parsed_chunks = chunks || Commiti::DiffParser.split_by_file(diff)
        files = build_file_stats(parsed_chunks)
        return diff.to_s[0, FALLBACK_BYTES] if files.empty?

        render_fallback_summary(files)
      end

      private

      def build_file_stats(chunks)
        chunks.map { |chunk| summarize_chunk(chunk) }
      end

      def summarize_chunk(chunk)
        status, additions, deletions = status_and_counts(chunk[:diff])
        {
          path: chunk[:path].to_s,
          additions: additions,
          deletions: deletions,
          status: status
        }
      end

      def status_and_counts(diff_text)
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

      def detect_status(line, current:)
        stripped = line.strip
        return 'added' if stripped.start_with?('new file mode')
        return 'deleted' if stripped.start_with?('deleted file mode')
        return 'renamed' if stripped.start_with?('rename from ') || stripped.start_with?('rename to ')

        current
      end

      def metadata_line?(line)
        line.start_with?('diff --git ', '+++', '---', '@@')
      end

      def render_fallback_summary(files)
        lines = [
          '### Diff Overview',
          "- Total files changed: #{files.length}",
          ''
        ]

        files.first(MAX_FILES_IN_SUMMARY).each do |file|
          lines.concat(render_file_section(file))
        end

        if files.length > MAX_FILES_IN_SUMMARY
          lines << "...and #{files.length - MAX_FILES_IN_SUMMARY} more files"
        end

        lines.join("\n").strip
      end

      def render_file_section(file)
        [
          "### #{file[:path]}",
          "- Status: #{file[:status]}",
          "- Added lines: #{file[:additions]}",
          "- Removed lines: #{file[:deletions]}",
          ''
        ]
      end
    end
  end
end
