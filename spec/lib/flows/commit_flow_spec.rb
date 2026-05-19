# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::Flows::CommitFlow do
  let(:options) { { auto_split: true, candidates: 1, no_copy: true } }
  let(:flow) { described_class.new(options: options) }
  let(:client) { instance_double('Commiti::GoogleClient') }

  before do
    allow(Commiti::Spinner).to receive(:run) { |_message, &block| block.call }
    allow(Commiti::CommitStaging).to receive(:prepare)
    allow(Commiti::GitReader).to receive(:staged_diff).and_return('diff --git a/a.rb b/a.rb')
    allow(Commiti::GoogleClient).to receive(:new).and_return(client)
    allow(flow).to receive(:maybe_copy_to_clipboard)
    allow(flow).to receive(:select_message).and_return('feat: grouped change')
    allow(flow).to receive(:generate_candidates).and_return(['feat: grouped change'])
    allow(Commiti::MessagePresenter).to receive(:print_summarization_notice)
  end

  it 'falls back to single commit path when grouping yields one group' do
    single_context = {
      change_groups: [{ id: 1, files: ['lib/a.rb'], chunks: [{ path: 'lib/a.rb', lines: [] }] }],
      summarized_result: { summarized: false, fallback_reason: nil, content: 'diff' },
      prompt: { system: 's', user: 'u' },
      diff_metadata: { docs_only: false, total_files: 1 }
    }

    allow(Commiti::FlowContextBuilder).to receive(:build).and_return(single_context)
    allow(flow).to receive(:finalize).and_return(:committed)
    expect(Commiti::GitWriter).not_to receive(:unstage_all)

    flow.run

    expect(flow).to have_received(:finalize).once
  end

  it 'stages groups sequentially and restages remaining changes when a group is skipped' do
    initial_context = {
      change_groups: [
        { id: 1, files: ['lib/a.rb'], chunks: [{ path: 'lib/a.rb', lines: ["diff --git a/lib/a.rb b/lib/a.rb\n"] }] },
        { id: 2, files: ['lib/b.rb'], chunks: [{ path: 'lib/b.rb', lines: ["diff --git a/lib/b.rb b/lib/b.rb\n"] }] }
      ],
      summarized_result: { summarized: false, fallback_reason: nil, content: 'diff' },
      prompt: { system: 's', user: 'u' },
      diff_metadata: { docs_only: false, total_files: 2 }
    }

    per_group_context = {
      change_groups: [],
      summarized_result: { summarized: false, fallback_reason: nil, content: 'diff' },
      prompt: { system: 's', user: 'u' },
      diff_metadata: { docs_only: false, total_files: 1 }
    }

    allow(Commiti::FlowContextBuilder).to receive(:build).and_return(initial_context, per_group_context, per_group_context)
    allow(Commiti::GitWriter).to receive(:unstage_all).and_return(true)
    allow(Commiti::GitWriter).to receive(:stage_files).and_return(true)
    allow(Commiti::GitWriter).to receive(:staged_changes?).and_return(true)
    allow(Commiti::GitWriter).to receive(:stage_all).and_return(true)
    allow(flow).to receive(:finalize).and_return(:committed, :skipped)

    flow.run

    expect(Commiti::GitWriter).to have_received(:unstage_all).once
    expect(Commiti::GitWriter).to have_received(:stage_files).with(['lib/a.rb']).once
    expect(Commiti::GitWriter).to have_received(:stage_files).with(['lib/b.rb']).once
    expect(Commiti::GitWriter).to have_received(:stage_all).once
  end
end
