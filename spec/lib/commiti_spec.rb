# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti do
  it 'loads core service constants' do
    expect(defined?(Commiti::GitReader)).to eq('constant')
    expect(defined?(Commiti::GitWriter)).to eq('constant')
    expect(defined?(Commiti::GoogleClient)).to eq('constant')
    expect(defined?(Commiti::DiffParser)).to eq('constant')
    expect(defined?(Commiti::DiffSummarizer)).to eq('constant')
    expect(defined?(Commiti::PromptBuilder)).to eq('constant')
    expect(defined?(Commiti::ChangelogBuilder)).to eq('constant')
    expect(defined?(Commiti::PrOpener)).to eq('constant')
    expect(defined?(Commiti::PrCreator)).to eq('constant')
    expect(defined?(Commiti::Flows::CommitFlow)).to eq('constant')
    expect(defined?(Commiti::Flows::ChangelogFlow)).to eq('constant')
    expect(defined?(Commiti::Flows::PrFlow)).to eq('constant')
  end
end
