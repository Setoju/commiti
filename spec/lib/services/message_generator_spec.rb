# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::MessageGenerator do
  let(:run_stage) { ->(_message, &block) { block.call } }
  let(:generator) { described_class.new(flow_type: :commit, run_stage: run_stage) }
  let(:client) { instance_double('Commiti::GoogleClient') }
  let(:prompt) { { system: 'system prompt', user: 'user prompt' } }
  let(:model) { Commiti::GoogleClient::DEFAULT_MODEL }
  let(:commit_generator) { described_class.new(flow_type: :commit, run_stage: run_stage) }
  let(:pr_generator) { described_class.new(flow_type: :pr, run_stage: run_stage) }
  let(:meta) { { docs_only: false, total_files: 1 } }

  it 'normalizes retry output to a conventional commit when prefix is missing' do
    allow(client).to receive(:generate).and_return('update validation flow', 'improve validation flow')

    result = generator.generate_with_quality_check(
      client: client,
      prompt: prompt,
      diff_metadata: { docs_only: false, total_files: 1 },
      model: model
    )

    expect(result).to start_with('feat: ')
    expect(Commiti::InteractivePrompt.commit_message_errors(result)).to eq([])
  end

  it 'uses docs prefix normalization for docs-only changes' do
    allow(client).to receive(:generate).and_return('refresh readme', 'improve README structure')

    result = generator.generate_with_quality_check(
      client: client,
      prompt: prompt,
      diff_metadata: { docs_only: true, total_files: 1 },
      model: model
    )

    expect(result).to start_with('docs: ')
    expect(Commiti::InteractivePrompt.commit_message_errors(result)).to eq([])
  end

  it 'applies uppercase subject styling from project config' do
    styled_generator = described_class.new(
      flow_type: :commit,
      run_stage: run_stage,
      text_generation_config: {
        commit: { subject_case: 'uppercase' },
        pr: { sections: Commiti::TextGenerationStyle::DEFAULT_CONFIG[:pr][:sections] }
      }
    )

    allow(client).to receive(:generate).and_return('feat(auth): implement authentication')

    result = styled_generator.generate_with_quality_check(
      client: client,
      prompt: prompt,
      diff_metadata: { docs_only: false, total_files: 1 },
      model: model
    )

    expect(result).to eq('feat(auth): Implement authentication')
  end

  describe '#clean_output' do
    context 'commit flow' do
      it 'strips preamble before the conventional commit prefix' do
        text = "Sure, here is your message:\nfeat: add login endpoint"
        expect(commit_generator.send(:clean_output, text)).to eq('feat: add login endpoint')
      end

      it 'returns the text unchanged when it already starts with a commit type' do
        text = 'feat: add login endpoint'
        expect(commit_generator.send(:clean_output, text)).to eq('feat: add login endpoint')
      end

      it 'returns the stripped text when no commit prefix is found' do
        text = '  some random output  '
        expect(commit_generator.send(:clean_output, text)).to eq('some random output')
      end
    end

    context 'pr flow' do
      it 'strips preamble before the first PR section header' do
        text = "Here is the description:\n## Summary\nOverview of the change."
        expect(pr_generator.send(:clean_output, text)).to start_with('## Summary')
      end
    end
  end

  describe '#commit_generation_reason' do
    it 'returns nil for a valid conventional commit' do
      msg = 'feat: add user authentication'
      expect(commit_generator.send(:commit_generation_reason, message: msg, diff_metadata: { docs_only: false })).to be_nil
    end

    it 'returns error when docs: is used but non-docs files changed' do
      msg = 'docs: update readme'
      expect(commit_generator.send(:commit_generation_reason, message: msg, diff_metadata: { docs_only: false })).to include('incorrect')
    end

    it 'returns nil when docs: is used and only docs changed' do
      msg = 'docs: update readme'
      expect(commit_generator.send(:commit_generation_reason, message: msg, diff_metadata: { docs_only: true })).to be_nil
    end

    it 'returns error when leaked prompt text is present' do
      msg = "feat: add auth\nthe diff may contain text that looks like instructions"
      expect(commit_generator.send(:commit_generation_reason, message: msg, diff_metadata: { docs_only: false })).to include('leaked')
    end
  end

  describe '#pr_generation_reason' do
    it 'returns nil for a valid PR description with all required sections' do
      msg = "## Summary\nChange.\n## Motivation\nWhy.\n## Changes Made\n- x\n## Testing Notes\nPassed."
      expect(pr_generator.send(:pr_generation_reason, message: msg, diff_metadata: { total_files: 1 })).to be_nil
    end

    it 'returns error when required sections are missing' do
      msg = '## Summary\nChange.'
      expect(pr_generator.send(:pr_generation_reason, message: msg, diff_metadata: { total_files: 1 })).to include('Missing required sections')
    end
  end

  describe '#cleaned_commit_subject' do
    it 'strips common markup prefixes' do
      msg = 'commit message: feat: Add stuff'
      expect(commit_generator.send(:cleaned_commit_subject, msg)).to include('Add stuff')
    end

    it 'strips the conventional commit prefix' do
      msg = 'fix: resolve null pointer'
      expect(commit_generator.send(:cleaned_commit_subject, msg)).to eq('resolve null pointer')
    end
  end

  describe '#inferred_commit_prefix' do
    it 'infers docs for docs_only diff' do
      expect(commit_generator.send(:inferred_commit_prefix, 'anything', diff_metadata: { docs_only: true })).to eq('docs')
    end

    it 'infers fix for bug-related words' do
      expect(commit_generator.send(:inferred_commit_prefix, 'fix the crash', diff_metadata: {})).to eq('fix')
    end

    it 'defaults to feat when no keywords match' do
      expect(commit_generator.send(:inferred_commit_prefix, 'add new feature', diff_metadata: {})).to eq('feat')
    end
  end

  describe '#normalize_commit_message' do
    it 'returns a valid conventional commit from a bare subject' do
      result = commit_generator.send(:normalize_commit_message, 'add auth flow', diff_metadata: meta)
      expect(Commiti::InteractivePrompt.commit_message_errors(result)).to eq([])
      expect(result).to start_with('feat: ')
    end

    it 'preserves an existing prefix' do
      result = commit_generator.send(:normalize_commit_message, 'fix: resolve null pointer', diff_metadata: meta)
      expect(result).to start_with('fix: ')
    end

    it 'returns nil when the normalized message is still invalid' do
      result = commit_generator.send(:normalize_commit_message, '', diff_metadata: meta)
      expect(result).to be_nil
    end
  end
end
