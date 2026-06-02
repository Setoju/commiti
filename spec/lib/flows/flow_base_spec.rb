# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::Flows::FlowBase do
  describe '#initialize' do
    it 'merges CLI options over config defaults' do
      flow = described_class.new(options: { model: 'custom-model', no_copy: true })
      expect(flow.send(:options)[:model]).to eq('custom-model')
      expect(flow.send(:options)[:no_copy]).to be(true)
    end

    it 'uses config defaults when CLI options are empty' do
      flow = described_class.new(options: {})
      expect(flow.send(:options)[:candidates]).to eq(1)
    end

    it 'handles nil options gracefully' do
      flow = described_class.new(options: nil)
      expect(flow.send(:options)[:candidates]).to eq(1)
    end
  end

  describe '#run_stage' do
    it 'delegates to Spinner.run and returns block value' do
      flow = described_class.new(options: {})
      allow(Commiti::Spinner).to receive(:run).and_yield
      result = flow.send(:run_stage, 'label') { 42 }
      expect(result).to eq(42)
    end
  end
end
