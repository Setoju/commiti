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
        selected_model = options[:model]

        context = Commiti::FlowContextBuilder.build(
          flow_type: flow_type,
          diff: diff,
          client: client,
          run_stage: method(:run_stage),
          model: selected_model
        )

        groups = context[:change_groups]
        if groups.length <= 1
          puts "\nAuto-split found a single connected change group. Falling back to single commit flow."
          Commiti::MessagePresenter.print_summarization_notice(context[:summarized_result])

          candidates = generate_candidates(
            client: client,
            prompt: context[:prompt],
            diff_metadata: context[:diff_metadata],
            model: selected_model
          )
          message = select_message(candidates)

          maybe_copy_to_clipboard(message)
          finalize(message)
          return
        end

        run_stage('Unstaging current index for grouped commit execution') { Commiti::GitWriter.unstage_all }

        puts "\nAuto-split detected #{groups.length} connected change groups."

        groups.each_with_index do |group, index|
          run_stage("Staging files for group #{index + 1}/#{groups.length}") { Commiti::GitWriter.stage_files(group[:files]) }

          next unless run_stage('Checking staged changes') { Commiti::GitWriter.staged_changes? }

          puts "\nGroup #{index + 1}/#{groups.length} files:"
          group[:files].each { |path| puts "- #{path}" }

          group_diff = group[:chunks].map { |chunk| chunk[:lines].join }.join
          group_context = Commiti::FlowContextBuilder.build(
            flow_type: flow_type,
            diff: group_diff,
            client: client,
            run_stage: method(:run_stage),
            model: selected_model
          )

          Commiti::MessagePresenter.print_summarization_notice(group_context[:summarized_result])

          candidates = generate_candidates(
            client: client,
            prompt: group_context[:prompt],
            diff_metadata: group_context[:diff_metadata],
            model: selected_model
          )
          message = select_message(candidates)

          maybe_copy_to_clipboard(message)
          result = finalize(message)

          if result != :committed
            puts "Stopping auto-split flow at group #{index + 1} because commit was skipped."
            run_stage('Restaging remaining uncommitted changes') { Commiti::GitWriter.stage_all }
            return
          end
        end
      rescue StandardError
        run_stage('Restaging uncommitted changes after failure') { Commiti::GitWriter.stage_all }
        raise
      end
    end
  end
end
