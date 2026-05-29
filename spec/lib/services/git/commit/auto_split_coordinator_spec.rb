# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::AutoSplitCoordinator do
  let(:options) { { model: 'gemma', diff_summary_workers: 2, text_generation: nil, no_copy: true } }
  let(:client) { instance_double('Commiti::GoogleClient') }
  let(:run_stage) { ->(_label, &block) { block.call } }
  let(:generated_message) { 'feat: test change' }
  let(:generate_candidates) { ->(**_kwargs) { [generated_message] } }
  let(:select_message) { ->(candidates) { candidates.first } }
  let(:captured_finalize_args) { [] }
  let(:finalize) { ->(msg) { captured_finalize_args << msg; :committed } }
  let(:maybe_copy_to_clipboard) { ->(_msg) {} }

  let(:coordinator) do
    described_class.new(
      options: options,
      client: client,
      model: options[:model],
      run_stage: run_stage,
      generate_candidates: generate_candidates,
      select_message: select_message,
      finalize: finalize,
      maybe_copy_to_clipboard: maybe_copy_to_clipboard
    )
  end

  let(:single_group_context) do
    {
      change_groups: [{ id: 1, files: ['lib/a.rb'], chunks: [{ path: 'lib/a.rb', lines: ["diff\n"] }] }],
      summarized_result: { summarized: false, fallback_reason: nil, content: 'diff' },
      prompt: { system: 's', user: 'u' },
      diff_metadata: { docs_only: false, total_files: 1 }
    }
  end

  let(:multi_group_context) do
    {
      change_groups: [
        { id: 1, files: ['lib/a.rb'], chunks: [{ path: 'lib/a.rb', lines: ["diff a\n"] }] },
        { id: 2, files: ['lib/b.rb'], chunks: [{ path: 'lib/b.rb', lines: ["diff b\n"] }] }
      ],
      summarized_result: { summarized: false, fallback_reason: nil, content: 'diff' },
      prompt: { system: 's', user: 'u' },
      diff_metadata: { docs_only: false, total_files: 2 }
    }
  end

  before do
    allow(Commiti::MessagePresenter).to receive(:print_summarization_notice)
  end

  describe '#run' do
    context 'when diff produces a single group' do
      before do
        allow(Commiti::FlowContextBuilder).to receive(:build).and_return(single_group_context)
      end

      it 'calls finalize once with the generated message' do
        coordinator.run(diff: 'diff text')
        expect(captured_finalize_args).to eq([generated_message])
      end

      it 'does not unstage the index' do
        expect(Commiti::GitWriter).not_to receive(:unstage_all!)
        coordinator.run(diff: 'diff text')
      end
    end

    context 'when diff produces multiple groups' do
      let(:per_group_context) do
        {
          change_groups: [],
          summarized_result: { summarized: false, fallback_reason: nil, content: 'diff' },
          prompt: { system: 's', user: 'u' },
          diff_metadata: { docs_only: false, total_files: 1 }
        }
      end

      before do
        allow(Commiti::FlowContextBuilder).to receive(:build).and_return(multi_group_context, per_group_context, per_group_context)
        allow(Commiti::GroupEditor).to receive(:edit) { |groups| groups }
        allow(Commiti::GitWriter).to receive(:unstage_all!)
        allow(Commiti::GitWriter).to receive(:stage_files!)
        allow(Commiti::GitWriter).to receive(:staged_changes?).and_return(true)
        allow(Commiti::GitWriter).to receive(:stage_all!)
      end

      it 'calls finalize once per group' do
        coordinator.run(diff: 'diff text')
        expect(captured_finalize_args.length).to eq(2)
      end

      it 'unstages the index before processing groups' do
        coordinator.run(diff: 'diff text')
        expect(Commiti::GitWriter).to have_received(:unstage_all!).once
      end
    end

    context 'when a group is skipped' do
      let(:per_group_context) do
        {
          change_groups: [],
          summarized_result: { summarized: false, fallback_reason: nil, content: 'diff' },
          prompt: { system: 's', user: 'u' },
          diff_metadata: { docs_only: false, total_files: 1 }
        }
      end
      let(:skip_finalize) { ->(msg) { captured_finalize_args << msg; :skipped } }
      let(:coordinator_with_skip) do
        described_class.new(
          options: options, client: client, model: options[:model],
          run_stage: run_stage, generate_candidates: generate_candidates,
          select_message: select_message, finalize: skip_finalize,
          maybe_copy_to_clipboard: maybe_copy_to_clipboard
        )
      end

      before do
        allow(Commiti::FlowContextBuilder).to receive(:build).and_return(multi_group_context, per_group_context)
        allow(Commiti::GroupEditor).to receive(:edit) { |groups| groups }
        allow(Commiti::GitWriter).to receive(:unstage_all!)
        allow(Commiti::GitWriter).to receive(:stage_files!)
        allow(Commiti::GitWriter).to receive(:staged_changes?).and_return(true)
        allow(Commiti::GitWriter).to receive(:stage_all!)
      end

      it 'stops after the skipped group and restages remaining changes' do
        coordinator_with_skip.run(diff: 'diff text')
        expect(captured_finalize_args.length).to eq(1)
        expect(Commiti::GitWriter).to have_received(:stage_all!).once
      end
    end
  end
end
