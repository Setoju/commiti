# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::GroupEditor do
  let(:chunk_a) { { path: 'lib/a.rb', lines: ["diff --git a/lib/a.rb b/lib/a.rb\n"] } }
  let(:chunk_a_spec) { { path: 'spec/a_spec.rb', lines: ["diff --git a/spec/a_spec.rb b/spec/a_spec.rb\n"] } }
  let(:chunk_readme) { { path: 'README.md', lines: ["diff --git a/README.md b/README.md\n"] } }

  it 'reassigns removed files to the best matching group' do
    groups = [
      { id: 1, files: ['lib/a.rb'], chunks: [chunk_a] },
      { id: 2, files: ['spec/a_spec.rb'], chunks: [chunk_a_spec] },
      { id: 3, files: ['README.md'], chunks: [chunk_readme] }
    ]

    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(true)
    allow(Commiti::InteractivePrompt).to receive(:ask_text).and_return('1', 'a', '')

    edited = described_class.edit(groups)

    expect(edited.length).to eq(2)
    expect(edited[0][:files]).to match_array(['lib/a.rb', 'spec/a_spec.rb'])
    expect(edited[1][:files]).to eq(['README.md'])
  end

  it 'creates a new group when removed files are unrelated' do
    groups = [
      { id: 1, files: ['lib/a.rb'], chunks: [chunk_a] },
      { id: 2, files: ['README.md'], chunks: [chunk_readme] }
    ]

    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(true)
    allow(Commiti::InteractivePrompt).to receive(:ask_text).and_return('2', 'a', '')

    edited = described_class.edit(groups)

    expect(edited.length).to eq(2)
    expect(edited[0][:files]).to eq(['lib/a.rb'])
    expect(edited[1][:files]).to eq(['README.md'])
  end

  it 'moves added files into the target group' do
    groups = [
      { id: 1, files: ['lib/a.rb'], chunks: [chunk_a] },
      { id: 2, files: ['README.md'], chunks: [chunk_readme] }
    ]

    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(true)
    allow(Commiti::InteractivePrompt).to receive(:ask_text).and_return('2', '1', '')

    edited = described_class.edit(groups)

    expect(edited.length).to eq(1)
    expect(edited[0][:files]).to match_array(['lib/a.rb', 'README.md'])
  end
end
