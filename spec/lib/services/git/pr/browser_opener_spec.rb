# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::PrBrowserOpener do
  describe '.open_in_browser' do
    it 'uses windows path when windows? is true' do
      allow(described_class).to receive(:windows?).and_return(true)
      allow(described_class).to receive(:open_windows_browser).with('http://x').and_return(true)
      expect(described_class.open_in_browser('http://x')).to be_nil
    end

    it 'raises when system fails' do
      allow(described_class).to receive(:windows?).and_return(false)
      allow(described_class).to receive(:mac?).and_return(false)
      allow(described_class).to receive(:system).and_return(false)
      expect { described_class.open_in_browser('http://x') }.to raise_error(RuntimeError)
    end
  end

  describe '.open_windows_browser' do
    it 'returns true when rundll32 succeeds' do
      allow(described_class).to receive(:system).with('rundll32', 'url.dll,FileProtocolHandler', 'http://x').and_return(true)
      expect(described_class.open_windows_browser('http://x')).to be true
    end

    it 'falls back to powershell when rundll32 fails' do
      allow(described_class).to receive(:system).with('rundll32', 'url.dll,FileProtocolHandler', 'http://x').and_return(false)
      allow(described_class).to receive(:system).with(
        'powershell', '-NoProfile', '-Command', '$u=$args[0]; Start-Process -FilePath $u', '--', 'http://x'
      ).and_return(true)
      expect(described_class.open_windows_browser('http://x')).to be true
    end
  end
end
