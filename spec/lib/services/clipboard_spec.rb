# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::Clipboard do
  describe '.copy' do
    it 'uses pbcopy on mac' do
      io = instance_double(IO, write: nil)
      allow(described_class).to receive(:platform).and_return(:mac)
      expect(IO).to receive(:popen).with('pbcopy', 'w').and_yield(io)

      expect(described_class.copy('hello')).to be_truthy
    end

    it 'uses xclip on linux when available' do
      io = instance_double(IO, write: nil)
      allow(described_class).to receive(:platform).and_return(:linux)
      allow(described_class).to receive(:command_exists?).with('xclip').and_return(true)
      expect(IO).to receive(:popen).with('xclip -selection clipboard', 'w').and_yield(io)

      expect(described_class.copy('hello')).to be_truthy
    end

    it 'uses xsel on linux when xclip is unavailable' do
      io = instance_double(IO, write: nil)
      allow(described_class).to receive(:platform).and_return(:linux)
      allow(described_class).to receive(:command_exists?).with('xclip').and_return(false)
      allow(described_class).to receive(:command_exists?).with('xsel').and_return(true)
      expect(IO).to receive(:popen).with('xsel --clipboard --input', 'w').and_yield(io)

      expect(described_class.copy('hello')).to be_truthy
    end

    it 'returns false when linux clipboard tools are unavailable' do
      allow(described_class).to receive(:platform).and_return(:linux)
      allow(described_class).to receive(:command_exists?).with('xclip').and_return(false)
      allow(described_class).to receive(:command_exists?).with('xsel').and_return(false)

      expect(described_class.copy('hello')).to be_falsey
    end

    it 'uses clip on windows' do
      io = instance_double(IO, write: nil)
      allow(described_class).to receive(:platform).and_return(:windows)
      expect(IO).to receive(:popen).with('clip', 'w').and_yield(io)

      expect(described_class.copy('hello')).to be_truthy
    end

    it 'returns false on unknown platform' do
      allow(described_class).to receive(:platform).and_return(:unknown)

      expect(described_class.copy('hello')).to be_falsey
    end
  end

  describe '.command_exists?' do
    it 'delegates to system which lookup' do
      expect(described_class).to receive(:system).with('which', 'xclip', out: File::NULL, err: File::NULL).and_return(true)

      expect(described_class.command_exists?('xclip')).to be(true)
    end
  end
end
