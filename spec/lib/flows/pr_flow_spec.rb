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

  it 'falls back to prefilled browser URL when provider is unsupported' do
    allow(Commiti::PrCreator).to receive(:create).and_return({ url: nil, reason: :unsupported_provider })
    expect(Commiti::PrOpener).to receive(:compare_url).and_return('https://bitbucket.org/acme/repo/pull-requests/new')
    expect(Commiti::InteractivePrompt).to receive(:ask_yes_no)
      .with('Open prefilled PR page in browser now?', default: :no)
      .and_return(false)

    flow.run
  end

  it 'falls back to prefilled browser URL when provider API call fails' do
    allow(Commiti::PrCreator).to receive(:create).and_return({
      url: nil,
      reason: :api_error,
      provider: :github,
      error: 'Connection timeout'
    })
    expect(Commiti::PrOpener).to receive(:compare_url).and_return('https://github.com/acme/repo/compare/main...feat-x')
    expect(Commiti::InteractivePrompt).to receive(:ask_yes_no)
      .with('Open prefilled PR page in browser now?', default: :no)
      .and_return(false)

    flow.run
  end

  it 'opens browser when user accepts API-created PR URL' do
    allow(Commiti::PrCreator).to receive(:create).and_return({ url: 'https://github.com/acme/repo/pull/7', reason: :created })
    expect(Commiti::InteractivePrompt).to receive(:ask_yes_no).with('Open created PR page in browser now?', default: :no)
                                                              .and_return(true)
    expect(Commiti::PrOpener).to receive(:open_in_browser).with('https://github.com/acme/repo/pull/7')

    flow.run
  end

  it 'opens browser when user accepts prefilled PR URL' do
    allow(Commiti::PrCreator).to receive(:create).and_return({ url: nil, reason: :missing_token, provider: :github })
    allow(Commiti::PrOpener).to receive(:compare_url).and_return('https://github.com/acme/repo/compare/main...feat-x?title=My+PR')
    expect(Commiti::InteractivePrompt).to receive(:ask_yes_no)
      .with('Open prefilled PR page in browser now?', default: :no)
      .and_return(true)
    expect(Commiti::PrOpener).to receive(:open_in_browser).with('https://github.com/acme/repo/compare/main...feat-x?title=My+PR')

    flow.run
  end

  it 'collects diff against base branch' do
    allow(Commiti::PrCreator).to receive(:create).and_return({ url: 'https://github.com/acme/repo/pull/7', reason: :created })
    expect(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(false)
    expect(Commiti::GitReader).to receive(:branch_diff).with(base_branch: 'main').and_return('diff content')

    flow.run
  end

  it 'respects custom base branch from options' do
    flow_with_custom_base = described_class.new(options: options.merge(base_branch: 'develop'))
    allow(Commiti::Spinner).to receive(:run) { |_message, &block| block.call }
    allow(Commiti::GitReader).to receive(:branch_diff).and_return('diff --git a/a.rb b/a.rb')
    allow(Commiti::GoogleClient).to receive(:new).and_return(client)
    allow(Commiti::FlowContextBuilder).to receive(:build).and_return(context)
    allow(flow_with_custom_base).to receive(:generate_candidates).and_return(['Generated PR body'])
    allow(flow_with_custom_base).to receive(:select_message).and_return('Generated PR body')
    allow(flow_with_custom_base).to receive(:maybe_copy_to_clipboard)
    allow(Commiti::MessagePresenter).to receive(:print_summarization_notice)
    allow(Commiti::GitWriter).to receive(:current_branch).and_return('feat-x')
    allow(Commiti::GitWriter).to receive(:origin_url).and_return('git@github.com:acme/repo.git')
    allow(Commiti::PrOpener).to receive(:suggest_title).and_return('My PR')
    allow(Commiti::PrCreator).to receive(:create).and_return({ url: 'https://github.com/acme/repo/pull/7', reason: :created })
    expect(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(false)
    expect(Commiti::GitReader).to receive(:branch_diff).with(base_branch: 'develop').and_return('diff content')

    flow_with_custom_base.run
  end

  it 'generates PR message using flow context' do
    allow(Commiti::PrCreator).to receive(:create).and_return({ url: 'https://github.com/acme/repo/pull/7', reason: :created })
    expect(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(false)
    expect(Commiti::FlowContextBuilder).to receive(:build).and_return(context)

    flow.run
  end

  it 'includes generated PR body in API creation call' do
    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(false)
    allow(flow).to receive(:select_message).and_return('My generated PR body with details')

    expect(Commiti::PrCreator).to receive(:create) do |args|
      expect(args[:body]).to eq('My generated PR body with details')
      { url: 'https://github.com/acme/repo/pull/7', reason: :created }
    end

    flow.run
  end

  it 'passes title from PrOpener to API creator' do
    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(false)
    allow(Commiti::PrOpener).to receive(:suggest_title).and_return('Suggested Title from Description')

    expect(Commiti::PrCreator).to receive(:create) do |args|
      expect(args[:title]).to eq('Suggested Title from Description')
      { url: 'https://github.com/acme/repo/pull/7', reason: :created }
    end

    flow.run
  end

  it 'passes config options to API creator' do
    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(false)

    expect(Commiti::PrCreator).to receive(:create) do |args|
      expect(args[:config]).to include(options)
      { url: 'https://github.com/acme/repo/pull/7', reason: :created }
    end

    flow.run
  end

  it 'does not prompt for browser when API succeeds without browser fallback' do
    allow(Commiti::PrCreator).to receive(:create).and_return({ url: 'https://github.com/acme/repo/pull/7', reason: :created })
    expect(Commiti::PrOpener).not_to receive(:compare_url)
    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(true)
    allow(Commiti::PrOpener).to receive(:open_in_browser)

    flow.run
  end
end
