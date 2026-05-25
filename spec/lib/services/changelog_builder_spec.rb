# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::ChangelogBuilder do
  it 'groups commits by conventional type and formats entries' do
    commits = [
      { sha: 'aaaaaaaa', subject: 'feat(api): add widget', body: '' },
      { sha: 'bbbbbbbb', subject: 'fix: patch issue', body: '' },
      { sha: 'cccccccc', subject: 'docs: update readme', body: '' },
      { sha: 'dddddddd', subject: 'misc cleanup', body: '' }
    ]

    output = described_class.build(commits, range: 'v1.2.0..HEAD')

    expect(output).to include('# Changelog (v1.2.0..HEAD)')
    expect(output).to include('## Features')
    expect(output).to include('- api: add widget (aaaaaaa)')
    expect(output).to include('## Fixes')
    expect(output).to include('- patch issue (bbbbbbb)')
    expect(output).to include('## Documentation')
    expect(output).to include('- update readme (ccccccc)')
    expect(output).to include('## Other')
    expect(output).to include('- misc cleanup (ddddddd)')
  end

  it 'raises when no commits are present' do
    expect do
      described_class.build([], range: 'v1.2.0..HEAD')
    end.to raise_error('No commits found in range.')
  end
end
