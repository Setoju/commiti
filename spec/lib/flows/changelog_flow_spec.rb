# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::Flows::ChangelogFlow do
  let(:flow) { described_class.new(options: { range: 'v1.2.0..HEAD' }) }

  before do
    allow(Commiti::ConfigLoader).to receive(:load).and_return({})
    allow(Commiti::Spinner).to receive(:run) { |_label, &block| block.call }
    allow(Commiti::MessagePresenter).to receive(:print_message)
  end

  describe '#run' do
    it 'groups commits by conventional type and formats entries' do
      commits = [
        { sha: 'aaaaaaaa', subject: 'feat(api): add widget', body: '' },
        { sha: 'bbbbbbbb', subject: 'fix: patch issue', body: '' },
        { sha: 'cccccccc', subject: 'docs: update readme', body: '' },
        { sha: 'dddddddd', subject: 'misc cleanup', body: '' }
      ]
      allow(Commiti::GitReader).to receive(:commits_in_range).and_return(commits)

      expect(Commiti::MessagePresenter).to receive(:print_message) do |changelog, **|
        expect(changelog).to include('# Changelog (v1.2.0..HEAD)')
        expect(changelog).to include('## Features')
        expect(changelog).to include('- api: add widget (aaaaaaa)')
        expect(changelog).to include('## Fixes')
        expect(changelog).to include('- patch issue (bbbbbbb)')
        expect(changelog).to include('## Documentation')
        expect(changelog).to include('- update readme (ccccccc)')
        expect(changelog).to include('## Other')
        expect(changelog).to include('- misc cleanup (ddddddd)')
      end

      flow.run
    end

    it 'raises when no commits are present' do
      allow(Commiti::GitReader).to receive(:commits_in_range).and_return([])

      expect { flow.run }.to raise_error('No commits found in range.')
    end

    it 'raises when range is blank' do
      flow_no_range = described_class.new(options: { range: '' })
      expect { flow_no_range.run }.to raise_error('Changelog range is required. Use --range v1.2.0..HEAD.')
    end
  end
end
