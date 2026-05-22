# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::CommitStaging do
  describe '.prepare' do
    let(:run_stage) { ->(_title, &block) { block.call } }

    it 'raises when status empty' do
      allow(Commiti::GitWriter).to receive(:status_short).and_return('')
      expect { described_class.prepare(run_stage: run_stage) }.to raise_error(RuntimeError)
    end

    it 'stages when user agrees and ensures staged changes' do
      allow(Commiti::GitWriter).to receive(:status_short).and_return('A file changed')
      allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(:yes)
      allow(Commiti::GitWriter).to receive(:stage_all!).and_return(true)
      allow(Commiti::GitWriter).to receive(:staged_changes?).and_return(true)
      expect { described_class.prepare(run_stage: run_stage) }.not_to raise_error
    end
  end
end
