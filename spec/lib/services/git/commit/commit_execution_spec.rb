# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::CommitExecution do
  describe '.maybe_commit' do
    let(:run_stage) { ->(_title, &block) { block.call } }
    let(:print_message) { ->(m) {} }

    it 'returns :skipped when user declines' do
      allow(Commiti::InteractivePrompt).to receive(:ask_commit_action).and_return(:no)
      expect(described_class.maybe_commit('msg', run_stage: run_stage, print_message: print_message)).to eq(:skipped)
    end

    it 'commits when yes and message valid' do
      allow(Commiti::InteractivePrompt).to receive(:ask_commit_action).and_return(:yes)
      allow(Commiti::InteractivePrompt).to receive(:commit_message_errors).and_return([])
      allow(Commiti::GitWriter).to receive(:commit_with_message_file).and_return('commit ok')

      result = described_class.maybe_commit('msg', run_stage: run_stage, print_message: print_message)
      expect(result).to(satisfy { |v| [:committed, [:committed, nil]].include?(v) })
    end
  end
end
