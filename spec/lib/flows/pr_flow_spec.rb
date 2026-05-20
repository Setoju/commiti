# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::Flows::PrFlow do
  let(:options) { { base_branch: 'main', candidates: 1, no_copy: true } }
  let(:flow) { described_class.new(options: options) }
  let(:client) { instance_double('Commiti::GoogleClient') }
  let(:context) do
    {
      change_groups: [],
      summarized_result: { summarized: false, fallback_reason: nil, content: 'diff' },
      prompt: { system: 's', user: 'u' },
      diff_metadata: { docs_only: false, total_files: 1 }
    }
  end

  before do
    allow(Commiti::Spinner).to receive(:run) { |_message, &block| block.call }
    allow(Commiti::GitReader).to receive(:branch_diff).and_return('diff --git a/a.rb b/a.rb')
    allow(Commiti::GoogleClient).to receive(:new).and_return(client)
    allow(Commiti::FlowContextBuilder).to receive(:build).and_return(context)
    allow(flow).to receive(:generate_candidates).and_return(['Generated PR body'])
    allow(flow).to receive(:select_message).and_return('Generated PR body')
    allow(flow).to receive(:maybe_copy_to_clipboard)
    allow(Commiti::MessagePresenter).to receive(:print_summarization_notice)
    allow(Commiti::GitWriter).to receive(:current_branch).and_return('feat-x')
    allow(Commiti::GitWriter).to receive(:origin_url).and_return('git@github.com:acme/repo.git')
    allow(Commiti::PrOpener).to receive(:suggest_title).and_return('My PR')
  end

  it 'uses provider API URL when token is configured and API call succeeds' do
    allow(Commiti::PrCreator).to receive(:create).and_return({ url: 'https://github.com/acme/repo/pull/7', reason: :created })
    expect(Commiti::PrOpener).not_to receive(:compare_url)
    expect(Commiti::InteractivePrompt).to receive(:ask_yes_no).with('Open created PR page in browser now?', default: :no)
                                                              .and_return(false)

    flow.run
  end

  it 'falls back to prefilled browser URL when provider token is missing' do
    allow(Commiti::PrCreator).to receive(:create).and_return({ url: nil, reason: :missing_token, provider: :github })
    expect(Commiti::PrOpener).to receive(:compare_url).and_return('https://github.com/acme/repo/compare/main...feat-x')
    expect(Commiti::InteractivePrompt).to receive(:ask_yes_no)
      .with('Open prefilled PR page in browser now?', default: :no)
      .and_return(false)

    flow.run
  end
end
