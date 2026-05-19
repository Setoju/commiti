# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Diff pipeline', :integration do
  let(:fake_summary_client_class) do
    Class.new do
      def generate(system:, user:, **_kwargs)
        return '- summarize file changes' if system.include?('provided diff chunk')

        user
      end
    end
  end

  it 'keeps file context then summarizes large diffs' do
    large_hunk = (1..10_000).map { |i| "+line #{i}" }.join("\n")
    diff = <<~DIFF
      diff --git a/app/models/user.rb b/app/models/user.rb
      index 111..222 100644
      --- a/app/models/user.rb
      +++ b/app/models/user.rb
      @@ -1 +1,10000 @@
      #{large_hunk}
    DIFF

    clipped = Commiti::GitReader.clip_diff_context(diff, max_bytes: Commiti::GitReader::MAX_DIFF_BYTES)
    result = Commiti::DiffSummarizer.summarize_if_needed(clipped, client: fake_summary_client_class.new)

    expect(clipped).to include('diff --git a/app/models/user.rb b/app/models/user.rb')
    expect(clipped).to include('@@ -1 +1,10000 @@')
    expect(result[:summarized]).to be(true)
    expect(result[:content]).to include('### app/models/user.rb')
  end

  it 'derives connected change groups from the diff context' do
    diff = <<~DIFF
      diff --git a/lib/services/message_generator.rb b/lib/services/message_generator.rb
      @@ -1 +1 @@
      -old
      +new
      diff --git a/spec/lib/services/message_generator_spec.rb b/spec/lib/services/message_generator_spec.rb
      @@ -1 +1 @@
      -old
      +new
      diff --git a/README.md b/README.md
      @@ -1 +1 @@
      -before
      +after
    DIFF

    context = Commiti::FlowContextBuilder.build(
      flow_type: :commit,
      diff: diff,
      client: fake_summary_client_class.new,
      run_stage: ->(_message, &block) { block.call },
      model: Commiti::GoogleClient::DEFAULT_MODEL
    )

    expect(context[:change_groups].length).to eq(2)
    expect(context[:change_groups][0][:files]).to eq([
                                                       'lib/services/message_generator.rb',
                                                       'spec/lib/services/message_generator_spec.rb'
                                                     ])
    expect(context[:change_groups][1][:files]).to eq(['README.md'])
  end
end
