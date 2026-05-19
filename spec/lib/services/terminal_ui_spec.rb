# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::TerminalUI do
  describe '.supports_ansi?' do
    it 'is false when stdout is not a tty' do
      allow($stdout).to receive(:tty?).and_return(false)

      expect(described_class.supports_ansi?).to be(false)
    end
  end

  describe '.status' do
    it 'returns plain text without ansi colors when ansi is unsupported' do
      allow(described_class).to receive(:supports_ansi?).and_return(false)

      expect(described_class.status(:success, 'Done')).to eq('✅ Done')
    end
  end
end
