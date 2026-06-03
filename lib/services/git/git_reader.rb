# frozen_string_literal: true

require 'open3'
require_relative 'diff_parser'

module Commiti
  module GitReader
    def self.staged_diff
      diff, status = Open3.capture2('git', 'diff', '--cached', '-U0')
      raise 'Failed to read staged diff.' unless status.success?
      raise 'No staged changes. Run `git add` first.' if diff.strip.empty?

      filtered_diff = filter_diff_noise(diff)
      Commiti::DiffParser.clip(filtered_diff)
    end

    def self.branch_diff(base_branch: 'main')
      raise 'Invalid branch name.' unless base_branch.match?(%r{\A[a-zA-Z0-9_\-./]+\z})

      diff, status = Open3.capture2('git', 'diff', '-U0', "#{base_branch}...HEAD")
      raise "Failed to read branch diff against '#{base_branch}'." unless status.success?
      raise "No diff found against '#{base_branch}'." if diff.strip.empty?

      filtered_diff = filter_diff_noise(diff)
      Commiti::DiffParser.clip(filtered_diff)
    end

    def self.recent_commits(count: 10)
      out, = Open3.capture2('git', 'log', '--oneline', "-#{count}")
      out
    end

    LOG_RECORD_SEPARATOR = "\x1e"
    LOG_FIELD_SEPARATOR = "\x1f"

    def self.recent_commit_messages(n: 50)
      format = ['%s', '%b'].join(LOG_FIELD_SEPARATOR) + LOG_RECORD_SEPARATOR
      output, err, status = Open3.capture3(
        'git',
        'log',
        '--no-color',
        '--no-merges',
        "--pretty=format:#{format}",
        '-n',
        n.to_i.to_s
      )
      raise "Failed to read recent git commits: #{err.strip.empty? ? output.strip : err.strip}" unless status.success?
      return [] if output.to_s.strip.empty?

      output.split(LOG_RECORD_SEPARATOR).filter_map do |record|
        next if record.strip.empty?

        subject, body = record.split(LOG_FIELD_SEPARATOR, 2)
        {
          subject: subject.to_s.strip,
          body: body.to_s
        }
      end
    end

    def self.remote_url(remote: 'origin')
      output, status = Open3.capture2('git', 'remote', 'get-url', remote)
      status.success? ? output.strip : nil
    rescue StandardError
      nil
    end

    def self.commits_in_range(range:)
      raise 'Invalid changelog range.' unless valid_range?(range)

      format = ['%H', '%s', '%b'].join(LOG_FIELD_SEPARATOR) + LOG_RECORD_SEPARATOR
      out, err, status = Open3.capture3('git', 'log', '--no-color', "--pretty=format:#{format}", range.to_s)
      raise "Failed to read git log for range '#{range}': #{err.strip.empty? ? out.strip : err.strip}" unless status.success?
      return [] if out.to_s.strip.empty?

      out.split(LOG_RECORD_SEPARATOR).filter_map do |record|
        next if record.strip.empty?

        sha, subject, body = record.split(LOG_FIELD_SEPARATOR, 3)
        {
          sha: sha.to_s.strip,
          subject: subject.to_s.strip,
          body: body.to_s
        }
      end
    end

    def self.valid_range?(range)
      range.to_s.match?(%r{\A[a-zA-Z0-9_\-./]+(\.\.\.?[a-zA-Z0-9_\-./]+)\z})
    end
    private_class_method :valid_range?

    LOCKFILE_PATTERNS = [
      /Gemfile\.lock/,
      /package-lock\.json/,
      /yarn\.lock/,
      /pnpm-lock\.yaml/,
      /composer\.lock/,
      /mix\.lock/,
      /Cargo\.lock/,
      /Pipfile\.lock/
    ].freeze

    def self.filter_diff_noise(diff)
      filtered_lines = []
      skip_chunk = false

      diff.each_line do |line|
        if line.start_with?('diff --git')
          path = extract_path_from_diff_header(line)
          is_lockfile = LOCKFILE_PATTERNS.any? { |pattern| path.match?(pattern) }
          is_binary_diff_header = line.include?('Binary files')

          if is_lockfile || is_binary_diff_header
            skip_chunk = true
            next
          else
            skip_chunk = false
          end
        end

        filtered_lines << line unless skip_chunk
      end
      filtered_lines.join
    end
    private_class_method :filter_diff_noise

    def self.extract_path_from_diff_header(line)
      match = line.chomp.match(%r{\Adiff --git a/(.+) b/(.+)\z})
      match ? match[2].strip : 'unknown'
    end
    private_class_method :extract_path_from_diff_header
  end
end
