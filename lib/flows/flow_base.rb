# frozen_string_literal: true

module Commiti
  module Flows
    class FlowBase
      def initialize(options:)
        @options = Commiti::ConfigLoader.load.merge(options || {})
      end

      private

      attr_reader :options

      def run_stage(message, &)
        Commiti::Spinner.run(message, &)
      end
    end
  end
end
