# frozen_string_literal: true

require 'open3'
require 'tempfile'

module Commiti
  module GitWriter
    def self.status_short
      out, status = Open3.capture2('git', 'status', '--short')
      raise 'Failed to read git status.' unless status.success?

      out
    end

    def self.staged_changes?
      out, status = Open3.capture2('git', 'diff', '--cached', '--name-only')
      raise 'Failed to read staged changes.' unless status.success?

      !out.strip.empty?
    end

    def self.stage_all
      out, err, status = Open3.capture3('git', 'add', '-A')
      raise "git add failed: #{err.strip.empty? ? out.strip : err.strip}" unless status.success?

      true
    end

    def self.unstage_all
      out, err, status = Open3.capture3('git', 'reset')
      raise "git reset failed: #{err.strip.empty? ? out.strip : err.strip}" unless status.success?

      true
    end

    def self.stage_files(paths)
      normalized = Array(paths).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      return true if normalized.empty?

      out, err, status = Open3.capture3('git', 'add', '--', *normalized)
      raise "git add failed: #{err.strip.empty? ? out.strip : err.strip}" unless status.success?

      true
    end

    def self.commit_with_message_file(message)
      Tempfile.create(['commiti-commit', '.txt']) do |file|
        file.write("#{message.to_s.rstrip}\n")
        file.flush

        out, err, status = Open3.capture3('git', 'commit', '--file', file.path)
        unless status.success?
          detail = err.strip.empty? ? out.strip : err.strip
          raise "git commit failed: #{detail}"
        end

        out
      end
    end

    def self.current_branch
      out, status = Open3.capture2('git', 'rev-parse', '--abbrev-ref', 'HEAD')
      raise 'Failed to read current branch.' unless status.success?

      out.strip
    end

    def self.origin_url
      out, status = Open3.capture2('git', 'remote', 'get-url', 'origin')
      raise "Failed to read git remote 'origin'." unless status.success?

      out.strip
    end
  end
end
