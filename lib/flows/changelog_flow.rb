# frozen_string_literal: true

module Commiti
  module Flows
    class ChangelogFlow < FlowBase
      def run
        range = options[:range].to_s.strip
        raise 'Changelog range is required. Use --range v1.2.0..HEAD.' if range.empty?

        commits = run_stage('Collecting commits') { Commiti::GitReader.commits_in_range(range: range) }
        changelog = run_stage('Formatting changelog') { Commiti::ChangelogBuilder.build(commits, range: range) }
        Commiti::MessagePresenter.print_message(changelog, title: 'Changelog')
      end
    end
  end
end
