# frozen_string_literal: true

module Commiti
  module Flows
    class BaseFlow
      def initialize(options:)
        # Merge defaults/config file with CLI options (CLI options win)
        @options = Commiti::ConfigLoader.load.merge(options || {})
      end

      def run
        prepare!
        diff = collect_diff
        client = Commiti::GoogleClient.new(config: options)
        selected_model = options[:model]
        context = Commiti::FlowContextBuilder.build(
          flow_type: flow_type,
          diff: diff,
          client: client,
          run_stage: method(:run_stage),
          model: selected_model,
          text_generation_config: options[:text_generation]
        )
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
      end

      private

      attr_reader :options

      def prepare!; end

      def collect_diff
        raise NotImplementedError, "#{self.class} must implement #collect_diff"
      end

      def flow_type
        raise NotImplementedError, "#{self.class} must implement #flow_type"
      end

      def finalize(_message); end

      def run_stage(message, &)
        Commiti::Spinner.run(message, &)
      end

      def generate_with_quality_check(client:, prompt:, diff_metadata:, model:)
        message_generator.generate_with_quality_check(
          client: client,
          prompt: prompt,
          diff_metadata: diff_metadata,
          model: model
        )
      end

      def generate_candidates(client:, prompt:, diff_metadata:, model:)
        count = options[:candidates].to_i
        message_generator.generate_candidates(
          client: client,
          prompt: prompt,
          diff_metadata: diff_metadata,
          count: count,
          model: model
        )
      end

      def select_message(candidates)
        Commiti::MessagePresenter.select_message(candidates)
      end

      def print_message(message)
        Commiti::MessagePresenter.print_message(message)
      end

      def maybe_copy_to_clipboard(message)
        Commiti::MessagePresenter.maybe_copy_to_clipboard(
          message,
          no_copy: options[:no_copy],
          run_stage: method(:run_stage)
        )
      end

      def message_generator
        @message_generator ||= Commiti::MessageGenerator.new(
          flow_type: flow_type,
          run_stage: method(:run_stage),
          text_generation_config: options[:text_generation]
        )
      end
    end
  end
end
