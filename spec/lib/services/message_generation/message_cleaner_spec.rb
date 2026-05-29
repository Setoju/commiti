# frozen_string_literal: true

require 'spec_helper'

class DummyCleaner
  include Commiti::MessageCleaner

  def initialize(flow_type, text_generation_config = {})
    @flow_type = flow_type
    @text_generation_config = text_generation_config
  end

  private

  attr_reader :flow_type, :text_generation_config
end

RSpec.describe Commiti::MessageCleaner do
  describe '#clean_output' do
    context 'commit flow' do
      let(:cleaner) { DummyCleaner.new(:commit) }

      it 'strips preamble before the conventional commit prefix' do
        text = "Sure, here is your message:\nfeat: add login endpoint"
        expect(cleaner.send(:clean_output, text)).to eq('feat: add login endpoint')
      end

      it 'returns the text unchanged when it already starts with a commit type' do
        text = "feat: add login endpoint"
        expect(cleaner.send(:clean_output, text)).to eq('feat: add login endpoint')
      end

      it 'returns the stripped text when no commit prefix is found' do
        text = "  some random output  "
        expect(cleaner.send(:clean_output, text)).to eq('some random output')
      end
    end

    context 'pr flow' do
      let(:cleaner) { DummyCleaner.new(:pr) }

      it 'strips preamble before the first PR section header' do
        text = "Here is the description:\n## Summary\nOverview of the change."
        expect(cleaner.send(:clean_output, text)).to start_with('## Summary')
      end
    end
  end
end
