# frozen_string_literal: true

module Commiti
  module Flows
    class ChangelogFlow < FlowBase
      TYPE_TITLES = {
        'feat' => 'Features',
        'fix' => 'Fixes',
        'docs' => 'Documentation',
        'perf' => 'Performance',
        'refactor' => 'Refactors',
        'test' => 'Tests',
        'chore' => 'Chores',
        'ci' => 'CI',
        'build' => 'Build',
        'style' => 'Style',
        'revert' => 'Reverts'
      }.freeze

      TYPE_PATTERN = /\A(?<type>[a-zA-Z]+)(?<scope>\([^)]+\))?(?<breaking>!)?:\s+(?<subject>.+)\z/.freeze

      def run
        range = options[:range].to_s.strip
        raise 'Changelog range is required. Use --range v1.2.0..HEAD.' if range.empty?

        commits = run_stage('Collecting commits') { Commiti::GitReader.commits_in_range(range: range) }
        changelog = run_stage('Formatting changelog') { build_changelog(commits, range: range) }
        Commiti::MessagePresenter.print_message(changelog, title: 'Changelog')
      end

      private

      def build_changelog(commits, range:)
        groups = Hash.new { |hash, key| hash[key] = [] }

        commits.each do |commit|
          subject = commit[:subject].to_s.strip
          next if subject.empty?
          next if subject.start_with?('Merge ')

          parsed = parse_subject(subject)
          group_title = TYPE_TITLES.fetch(parsed[:type], 'Other')
          groups[group_title] << format_entry(commit, parsed)
        end

        ordered_titles = TYPE_TITLES.values + ['Other']
        lines = ["# Changelog (#{range})", '']
        ordered_titles.each do |title|
          entries = groups[title]
          next if entries.empty?

          lines << "## #{title}"
          lines.concat(entries.map { |entry| "- #{entry}" })
          lines << ''
        end

        raise 'No commits found in range.' if lines.length <= 2

        lines.join("\n").rstrip
      end

      def parse_subject(subject)
        match = subject.match(TYPE_PATTERN)
        return { type: 'other', scope: nil, subject: subject, breaking: false } unless match

        {
          type: match[:type].downcase,
          scope: match[:scope]&.tr('()', ''),
          subject: match[:subject].to_s.strip,
          breaking: !match[:breaking].nil?
        }
      end

      def format_entry(commit, parsed)
        short_sha = commit[:sha].to_s[0, 7]
        label = parsed[:subject]
        label = "#{parsed[:scope]}: #{label}" if parsed[:scope]
        label = "BREAKING: #{label}" if parsed[:breaking]
        "#{label} (#{short_sha})"
      end
    end
  end
end
