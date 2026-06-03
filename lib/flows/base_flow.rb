# frozen_string_literal: true

module Commiti
  module Flows
    class BaseFlow
      def initialize(options:)
        @options = Commiti::ConfigLoader.load.merge(options || {})
      end

      def run
        prepare!
        diff = collect_diff
        client = Commiti::ClientFactory.build(config: options)
        selected_model = options[:model]
        style_profile = style_profile_for_flow
        context = Commiti::FlowContextBuilder.build(
          flow_type: flow_type,
          diff: diff,
          client: client,
          run_stage: method(:run_stage),
          model: selected_model,
          text_generation_config: options[:text_generation],
          style_profile: style_profile,
          worker_count: options[:diff_summary_workers]
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

      def run_stage(message, &)
        Commiti::Spinner.run(message, &)
      end

      def prepare!; end

      def collect_diff
        raise NotImplementedError, "#{self.class} must implement #collect_diff"
      end

      def flow_type
        raise NotImplementedError, "#{self.class} must implement #flow_type"
      end

      def finalize(_message); end

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

      def style_profile_for_flow
        return nil unless flow_type == :commit
        return options[:style_snapshot] if options[:style_snapshot]
        return nil if options[:style_learning] == false

        Commiti::StyleAnalyzer.analyze(lookback: options[:style_lookback])
      end
    end
  end
end
