# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::Clipboard do
  describe '.platform' do
    it 'returns a known platform symbol' do
      sym = described_class.platform
      expect(%i[mac linux windows unknown]).to include(sym)
    end
  end

  describe '.copy' do
    it 'calls pbcopy on mac' do
      allow(described_class).to receive(:platform).and_return(:mac)
      expect(IO).to receive(:popen).with('pbcopy', 'w')
      described_class.copy('x')
    end

    it 'returns :copied on windows' do
      allow(described_class).to receive(:platform).and_return(:windows)
      allow(IO).to receive(:popen)
      expect(described_class.copy('x')).to eq(:copied)
    end
  end
end
