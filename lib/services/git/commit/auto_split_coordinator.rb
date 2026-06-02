# frozen_string_literal: true

module Commiti
  class AutoSplitCoordinator
    def initialize(options:, client:, model:, run_stage:, generate_candidates:, select_message:, finalize:, maybe_copy_to_clipboard:)
      @options = options
      @client = client
      @model = model
      @run_stage = run_stage
      @generate_candidates = generate_candidates
      @select_message = select_message
      @finalize = finalize
      @maybe_copy_to_clipboard = maybe_copy_to_clipboard
    end

    def run(diff:)
      context = build_context(diff: diff)
      return run_single_group_context(context: context) if single_group?(context)

      run_grouped_context(context: context)
    end

    private

    attr_reader :options, :client, :model, :run_stage, :generate_candidates, :select_message, :finalize, :maybe_copy_to_clipboard

    def single_group?(context)
      context[:change_groups].length <= 1
    end

    def build_context(diff:)
      Commiti::FlowContextBuilder.build(
        flow_type: :commit,
        diff: diff,
        client: client,
        run_stage: run_stage,
        model: model,
        text_generation_config: options[:text_generation],
        worker_count: options[:diff_summary_workers]
      )
    end

    def run_single_group_context(context:)
      puts "\n#{Commiti::TerminalUI.status(:info, 'Auto-split found a single connected change group. Falling back to single commit flow.')}"
      Commiti::MessagePresenter.print_summarization_notice(context[:summarized_result])

      message = generate_message_for_context(context: context)
      maybe_copy_to_clipboard.call(message)
      finalize.call(message)
    end

    def run_grouped_context(context:)
      groups = Commiti::GroupEditor.edit(context[:change_groups])
      if groups.length <= 1
        single_context = groups.first ? build_context(diff: group_diff(groups.first)) : context
        return run_single_group_context(context: single_context)
      end

      run_stage.call('Unstaging current index for grouped commit execution') { Commiti::GitWriter.unstage_all! }

      puts "\n#{Commiti::TerminalUI.status(:info, "Auto-split detected #{groups.length} connected change groups.")}"

      groups.each_with_index do |group, index|
        break if process_group(group: group, index: index, total: groups.length) == :stop
      end
    end

    def process_group(group:, index:, total:)
      run_stage.call("Staging files for group #{index + 1}/#{total}") { Commiti::GitWriter.stage_files!(group[:files]) }
      return :continue unless run_stage.call('Checking staged changes') { Commiti::GitWriter.staged_changes? }

      puts "\n#{Commiti::TerminalUI.panel("Group #{index + 1}/#{total} files", Commiti::TerminalUI.bullets(group[:files]))}\n"

      group_context = build_context(diff: group_diff(group))
      Commiti::MessagePresenter.print_summarization_notice(group_context[:summarized_result])

      message = generate_message_for_context(context: group_context)
      maybe_copy_to_clipboard.call(message)
      return :continue if finalize.call(message) == :committed

      puts Commiti::TerminalUI.status(:warn, "Stopping auto-split flow at group #{index + 1} because commit was skipped.")
      run_stage.call('Restaging remaining uncommitted changes') { Commiti::GitWriter.stage_all! }
      :stop
    end

    def generate_message_for_context(context:)
      candidates = generate_candidates.call(
        client: client,
        prompt: context[:prompt],
        diff_metadata: context[:diff_metadata],
        model: model
      )
      select_message.call(candidates)
    end

    def group_diff(group)
      group[:chunks].map { |chunk| chunk[:lines].join }.join
    end
  end
end
