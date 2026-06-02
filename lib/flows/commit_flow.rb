# frozen_string_literal: true

module Commiti
  module Flows
    class CommitFlow < BaseFlow
      def run
        return super unless options[:auto_split]

        run_auto_split
      end

      private

      def flow_type
        :commit
      end

      def prepare!
        Commiti::CommitStaging.prepare(run_stage: method(:run_stage))
      end

      def collect_diff
        run_stage('Collecting staged diff') { Commiti::GitReader.staged_diff }
      end

      def finalize(message)
        Commiti::CommitExecution.maybe_commit(
          message,
          run_stage: method(:run_stage),
          print_message: method(:print_message)
        )
      end

      def run_auto_split
        prepare!
        diff = collect_diff
        client = Commiti::GoogleClient.new(config: options)
        model = options[:model]

        Commiti::AutoSplitCoordinator.new(
          options: options,
          client: client,
          model: model,
          run_stage: method(:run_stage),
          generate_candidates: method(:generate_candidates),
          select_message: method(:select_message),
          finalize: method(:finalize),
          maybe_copy_to_clipboard: method(:maybe_copy_to_clipboard)
        ).run(diff: diff)
      rescue StandardError
        run_stage('Restaging uncommitted changes after failure') { Commiti::GitWriter.stage_all! }
        raise
      end
    end
  end
end
