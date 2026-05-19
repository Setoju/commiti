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
        context = build_context(diff:, client:, model: selected_model)

        return run_single_group_context(context:, client:, model: selected_model) if single_group?(context)

        run_grouped_context(context:, client:, model: selected_model)
      rescue StandardError
        run_stage('Restaging uncommitted changes after failure') { Commiti::GitWriter.stage_all! }
        raise
      end

      def single_group?(context)
        context[:change_groups].length <= 1
      end

      def run_single_group_context(context:, client:, model:)
        message = 'Auto-split found a single connected change group. Falling back to single commit flow.'
        puts "\n#{Commiti::TerminalUI.status(:info, message)}"
        Commiti::MessagePresenter.print_summarization_notice(context[:summarized_result])

        message = generate_message_for_context(context:, client:, model:)
        maybe_copy_to_clipboard(message)
        finalize(message)
      end

      def run_grouped_context(context:, client:, model:)
        groups = context[:change_groups]
        run_stage('Unstaging current index for grouped commit execution') { Commiti::GitWriter.unstage_all! }

        puts "\n#{Commiti::TerminalUI.status(:info, "Auto-split detected #{groups.length} connected change groups.")}"

        groups.each_with_index do |group, index|
          break if process_group(group:, index:, total: groups.length, client:, model:) == :stop
        end
      end

      def process_group(group:, index:, total:, client:, model:)
        run_stage("Staging files for group #{index + 1}/#{total}") { Commiti::GitWriter.stage_files!(group[:files]) }
        return :continue unless run_stage('Checking staged changes') { Commiti::GitWriter.staged_changes? }

        puts "\n#{Commiti::TerminalUI.header("Group #{index + 1}/#{total} files")}:"
        group[:files].each { |path| puts "- #{path}" }

        group_context = build_context(diff: group_diff(group), client:, model:)
        Commiti::MessagePresenter.print_summarization_notice(group_context[:summarized_result])

        message = generate_message_for_context(context: group_context, client:, model:)
        maybe_copy_to_clipboard(message)
        return :continue if finalize(message) == :committed

        stop_message = "Stopping auto-split flow at group #{index + 1} because commit was skipped."
        puts Commiti::TerminalUI.status(:warn, stop_message)
        run_stage('Restaging remaining uncommitted changes') { Commiti::GitWriter.stage_all! }
        :stop
      end

      def build_context(diff:, client:, model:)
        Commiti::FlowContextBuilder.build(
          flow_type: flow_type,
          diff: diff,
          client: client,
          run_stage: method(:run_stage),
          model: model
        )
      end

      def generate_message_for_context(context:, client:, model:)
        candidates = generate_candidates(
          client: client,
          prompt: context[:prompt],
          diff_metadata: context[:diff_metadata],
          model: model
        )

        select_message(candidates)
      end

      def group_diff(group)
        group[:chunks].map { |chunk| chunk[:lines].join }.join
      end
    end
  end
end
