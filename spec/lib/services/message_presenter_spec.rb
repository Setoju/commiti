# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::MessagePresenter do
  describe '.select_message' do
    it 'returns the single candidate without prompting' do
      expect { described_class.select_message(['one']) }.to output.to_stdout
    end

    it 'prompts and selects when multiple candidates' do
      allow(Commiti::InteractivePrompt).to receive(:ask_candidate_selection).and_return(1)
      out = capture_stdout do
        result = described_class.select_message(%w[a b])
        expect(result).to eq('b')
      end
      expect(out).to include('Using candidate')
    end
  end

  describe '.maybe_copy_to_clipboard' do
    it 'prints success when copied' do
      run_stage = ->(_title, &block) { block.call }
      allow(Commiti::Clipboard).to receive(:copy).and_return(:copied)
      expect do
        described_class.maybe_copy_to_clipboard('x', no_copy: false, run_stage: run_stage)
      end.to output(/Copied output to clipboard/).to_stdout
    end

    it 'prints warning when not copied' do
      run_stage = ->(_title, &block) { block.call }
      allow(Commiti::Clipboard).to receive(:copy).and_return(nil)
      expect do
        described_class.maybe_copy_to_clipboard('x', no_copy: false, run_stage: run_stage)
      end.to output(/Clipboard unavailable/).to_stdout
    end
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end
