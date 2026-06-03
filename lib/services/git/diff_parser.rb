# frozen_string_literal: true

module Commiti
  module DiffParser
    DOC_EXTENSIONS = %w[.md .markdown .rst .adoc .txt].freeze

    def self.split_by_file_lines(diff)
      chunks = []
      current_path = nil
      current_lines = []

      diff.to_s.each_line do |line|
        if line.start_with?('diff --git ')
          chunks << { path: current_path, lines: current_lines } if current_path

          current_path = extract_path(line)
          current_lines = [line]
        else
          current_lines << line
        end
      end

      chunks << { path: current_path, lines: current_lines } if current_path
      chunks
    end

    def self.split_by_file(diff)
      split_by_file_lines(diff).map do |chunk|
        { path: chunk[:path], diff: chunk[:lines].join }
      end
    end

    def self.metadata_from_line_chunks(chunks)
      files = chunks.map { |chunk| chunk[:path].to_s }.reject(&:empty?).uniq
      {
        files: files,
        total_files: files.length,
        docs_only: docs_only_files?(files)
      }
    end

    def self.metadata(diff)
      metadata_from_line_chunks(split_by_file_lines(diff))
    end

    def self.docs_only_files?(files)
      return false if files.empty?

      files.all? do |path|
        normalized = path.to_s.downcase
        DOC_EXTENSIONS.any? { |ext| normalized.end_with?(ext) } ||
          normalized.start_with?('docs/') ||
          normalized.include?('/docs/')
      end
    end

    def self.extract_path(line)
      match = line.chomp.match(%r{\Adiff --git a/(.+) b/(.+)\z})
      match ? match[2].strip : 'unknown'
    end
    private_class_method :extract_path

    MAX_DIFF_BYTES = 50_000
    TRUNCATION_NOTICE = "\n# ... diff clipped by Commiti to preserve context under size limit\n"

    def self.clip(diff, max_bytes: MAX_DIFF_BYTES)
      return diff if diff.bytesize <= max_bytes

      chunks = split_by_file_lines(diff)
      clipped = if chunks.empty?
                  diff.byteslice(0, max_bytes)
                else
                  clip_chunks(chunks, max_bytes: max_bytes)
                end

      append_notice(clipped, max_bytes: max_bytes)
    end

    def self.clip_chunks(chunks, max_bytes:)
      output = +''

      chunks.each do |chunk|
        remaining = max_bytes - output.bytesize
        break if remaining <= 0

        chunk_text = chunk[:lines].join
        if chunk_text.bytesize <= remaining
          output << chunk_text
          next
        end

        output << clip_single_chunk(chunk[:lines], max_bytes: remaining)
        break
      end

      if output.empty?
        first_chunk_text = chunks.first[:lines].join
        return first_chunk_text.byteslice(0, max_bytes)
      end

      output
    end
    private_class_method :clip_chunks

    def self.clip_single_chunk(lines, max_bytes:)
      output = +''
      return output if max_bytes <= 0

      header_lines, hunks = partition_chunk_lines(lines)
      append_lines_with_limit(output, header_lines, max_bytes: max_bytes)
      return output if hunks.empty?

      append_hunks_with_limit(output, hunks, max_bytes: max_bytes)
      output
    end
    private_class_method :clip_single_chunk

    def self.partition_chunk_lines(lines)
      header_lines = []
      hunks = []
      current_hunk = nil

      lines.each do |line|
        if line.start_with?('@@')
          current_hunk = [line]
          hunks << current_hunk
        elsif current_hunk
          current_hunk << line
        else
          header_lines << line
        end
      end

      [header_lines, hunks]
    end
    private_class_method :partition_chunk_lines

    def self.append_lines_with_limit(output, lines, max_bytes:)
      lines.each do |line|
        break if output.bytesize + line.bytesize > max_bytes

        output << line
      end
    end
    private_class_method :append_lines_with_limit

    def self.append_hunks_with_limit(output, hunks, max_bytes:)
      hunks.each do |hunk|
        hunk_text = hunk.join
        if output.bytesize + hunk_text.bytesize <= max_bytes
          output << hunk_text
          next
        end

        append_partial_hunk(output, hunk, max_bytes: max_bytes)
        break
      end
    end
    private_class_method :append_hunks_with_limit

    def self.append_partial_hunk(output, hunk, max_bytes:)
      hunk_header = hunk.first
      return if output.bytesize + hunk_header.bytesize > max_bytes

      output << hunk_header
      append_lines_with_limit(output, hunk[1..].to_a, max_bytes: max_bytes)
    end
    private_class_method :append_partial_hunk

    def self.append_notice(clipped_diff, max_bytes:)
      safe_clipped = clipped_diff.to_s
      return safe_clipped if safe_clipped.bytesize >= max_bytes && max_bytes <= TRUNCATION_NOTICE.bytesize

      return safe_clipped + TRUNCATION_NOTICE if safe_clipped.bytesize + TRUNCATION_NOTICE.bytesize <= max_bytes

      available = max_bytes - TRUNCATION_NOTICE.bytesize
      return safe_clipped.byteslice(0, max_bytes) if available <= 0

      safe_clipped.byteslice(0, available) + TRUNCATION_NOTICE
    end
    private_class_method :append_notice
  end
end
