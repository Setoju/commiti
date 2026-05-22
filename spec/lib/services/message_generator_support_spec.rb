# frozen_string_literal: true

require 'spec_helper'

class DummyGenerator
  include Commiti::MessageGeneratorSupport

  def flow_type = :commit
  def text_generation_config = {}
end

RSpec.describe Commiti::MessageGeneratorSupport do
  let(:dummy) { DummyGenerator.new }

  describe '#cleaned_commit_subject' do
    it 'strips common prefixes and marks' do
      msg = 'commit message: feat: Add stuff'
      expect(dummy.send(:cleaned_commit_subject, msg)).to include('Add stuff')
    end
  end

  describe '#inferred_commit_prefix' do
    it 'infers docs for docs_only' do
      expect(dummy.send(:inferred_commit_prefix, 'anything', diff_metadata: { docs_only: true })).to eq('docs')
    end

    it 'infers fix for bug words' do
      expect(dummy.send(:inferred_commit_prefix, 'fix something', diff_metadata: {})).to eq('fix')
    end
  end

  describe '#commit_generation_reason' do
    it 'returns error when docs: used but non-docs present' do
      msg = 'docs: update'
      reason = dummy.send(:commit_generation_reason, message: msg, diff_metadata: { docs_only: false })
      expect(reason).to include('incorrect')
    end
  end
end
