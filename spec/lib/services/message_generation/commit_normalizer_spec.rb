# frozen_string_literal: true

require 'spec_helper'

class DummyNormalizer
  include Commiti::CommitNormalizer

  def initialize(text_generation_config = Commiti::TextGenerationStyle::DEFAULT_CONFIG)
    @text_generation_config = text_generation_config
  end

  private

  attr_reader :text_generation_config
end

RSpec.describe Commiti::CommitNormalizer do
  let(:normalizer) { DummyNormalizer.new }
  let(:meta) { { docs_only: false, total_files: 1 } }

  describe '#cleaned_commit_subject' do
    it 'strips common markup prefixes' do
      msg = 'commit message: feat: Add stuff'
      expect(normalizer.send(:cleaned_commit_subject, msg)).to include('Add stuff')
    end

    it 'strips the conventional commit prefix' do
      msg = 'fix: resolve null pointer'
      expect(normalizer.send(:cleaned_commit_subject, msg)).to eq('resolve null pointer')
    end
  end

  describe '#inferred_commit_prefix' do
    it 'infers docs for docs_only diff' do
      expect(normalizer.send(:inferred_commit_prefix, 'anything', diff_metadata: { docs_only: true })).to eq('docs')
    end

    it 'infers fix for bug-related words' do
      expect(normalizer.send(:inferred_commit_prefix, 'fix the crash', diff_metadata: {})).to eq('fix')
    end

    it 'defaults to feat when no keywords match' do
      expect(normalizer.send(:inferred_commit_prefix, 'add new feature', diff_metadata: {})).to eq('feat')
    end
  end

  describe '#normalize_commit_message' do
    it 'returns a valid conventional commit from a bare subject' do
      result = normalizer.send(:normalize_commit_message, 'add auth flow', diff_metadata: meta)
      expect(Commiti::InteractivePrompt.commit_message_errors(result)).to eq([])
      expect(result).to start_with('feat: ')
    end

    it 'preserves an existing prefix' do
      result = normalizer.send(:normalize_commit_message, 'fix: resolve null pointer', diff_metadata: meta)
      expect(result).to start_with('fix: ')
    end

    it 'returns nil when the normalized message is still invalid' do
      result = normalizer.send(:normalize_commit_message, '', diff_metadata: meta)
      expect(result).to be_nil
    end
  end
end
