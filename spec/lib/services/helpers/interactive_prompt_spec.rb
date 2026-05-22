# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::InteractivePrompt do
  describe '.ask_yes_no' do
    it 'returns :yes for yes answers' do
      allow(described_class).to receive(:read_input).and_return('y')
      expect(described_class.ask_yes_no('q')).to eq(:yes)
    end

    it 'returns nil for no answers' do
      allow(described_class).to receive(:read_input).and_return('n')
      expect(described_class.ask_yes_no('q')).to be_nil
    end

    it 'respects default when input is nil' do
      allow(described_class).to receive(:read_input).and_return(nil)
      expect(described_class.ask_yes_no('q', default: :yes)).to eq(:yes)
    end
  end

  describe '.ask_candidate_selection' do
    it 'returns 0 when count <= 1' do
      expect(described_class.ask_candidate_selection(1)).to eq(0)
    end

    it 'returns default-1 when input empty' do
      allow(described_class).to receive(:read_input).and_return('')
      expect(described_class.ask_candidate_selection(3, default: 2)).to eq(1)
    end

    it 'loops until valid selection' do
      allow(described_class).to receive(:read_input).and_return('x', '2')
      expect(described_class.ask_candidate_selection(3, default: 1)).to eq(1)
    end
  end

  describe '.commit_message_errors' do
    it 'flags empty message' do
      expect(described_class.commit_message_errors('')).to include('Message cannot be empty.')
    end

    it 'checks prefix and length' do
      long = "feat: #{'a' * 200}"
      errors = described_class.commit_message_errors(long)
      expect(errors.any? { |e| e.include?('First line must start') } || errors.any? { |e| e.include?('should be') }).to be true
    end
  end

  describe '.editor_command' do
    around do |example|
      orig_visual = ENV.fetch('VISUAL', nil)
      orig_editor = ENV.fetch('EDITOR', nil)
      ENV['VISUAL'] = nil
      ENV['EDITOR'] = nil
      example.run
      ENV['VISUAL'] = orig_visual
      ENV['EDITOR'] = orig_editor
    end

    it 'defaults to vi on non-windows' do
      allow(described_class).to receive(:windows?).and_return(false)
      expect(described_class.editor_command).to eq(['vi'])
    end

    it 'adds --wait for code editor' do
      allow(described_class).to receive(:windows?).and_return(false)
      ENV['VISUAL'] = 'code'
      expect(described_class.editor_command).to include('--wait')
    end
  end
end
