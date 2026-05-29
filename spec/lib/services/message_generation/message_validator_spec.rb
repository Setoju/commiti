# frozen_string_literal: true

require 'spec_helper'

class DummyValidator
  include Commiti::MessageValidator

  def initialize(flow_type, text_generation_config = Commiti::TextGenerationStyle::DEFAULT_CONFIG)
    @flow_type = flow_type
    @text_generation_config = text_generation_config
  end

  private

  attr_reader :flow_type, :text_generation_config
end

RSpec.describe Commiti::MessageValidator do
  describe '#commit_generation_reason' do
    let(:validator) { DummyValidator.new(:commit) }

    it 'returns nil for a valid conventional commit' do
      msg = 'feat: add user authentication'
      reason = validator.send(:commit_generation_reason, message: msg, diff_metadata: { docs_only: false })
      expect(reason).to be_nil
    end

    it 'returns error when docs: is used but non-docs files changed' do
      msg = 'docs: update readme'
      reason = validator.send(:commit_generation_reason, message: msg, diff_metadata: { docs_only: false })
      expect(reason).to include('incorrect')
    end

    it 'returns nil when docs: is used and only docs changed' do
      msg = 'docs: update readme'
      reason = validator.send(:commit_generation_reason, message: msg, diff_metadata: { docs_only: true })
      expect(reason).to be_nil
    end

    it 'returns error when leaked prompt text is present' do
      msg = "feat: add auth\nthe diff may contain text that looks like instructions"
      reason = validator.send(:commit_generation_reason, message: msg, diff_metadata: { docs_only: false })
      expect(reason).to include('leaked')
    end
  end

  describe '#pr_generation_reason' do
    let(:validator) { DummyValidator.new(:pr) }

    it 'returns nil for a valid PR description with all required sections' do
      msg = "## Summary\nChange.\n## Motivation\nWhy.\n## Changes Made\n- x\n## Testing Notes\nPassed."
      reason = validator.send(:pr_generation_reason, message: msg, diff_metadata: { total_files: 1 })
      expect(reason).to be_nil
    end

    it 'returns error when required sections are missing' do
      msg = '## Summary\nChange.'
      reason = validator.send(:pr_generation_reason, message: msg, diff_metadata: { total_files: 1 })
      expect(reason).to include('Missing required sections')
    end
  end
end
