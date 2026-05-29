# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::DiffSummarizer do
  let(:small_diff) { "diff --git a/a.rb b/a.rb\n@@ -1 +1 @@\n-old\n+new\n" }

  describe '.summarize_if_needed' do
    let(:client) { instance_double('client') }

    it 'returns original content when diff is under threshold' do
      result = described_class.summarize_if_needed(small_diff, client: client)

      expect(result[:summarized]).to be(false)
      expect(result[:content]).to eq(small_diff)
      expect(result[:fallback_reason]).to be_nil
    end

    it 'passes worker_count through to summarize_chunks' do
      large_diff = "diff --git a/foo.rb b/foo.rb\n#{'+' * 9000}"
      allow(Commiti::DiffParser).to receive(:split_by_file).and_return(
        [{ path: 'foo.rb', diff: large_diff }]
      )
      expect(Commiti::DiffSummarizer::BatchRunner).to receive(:summarize_chunks).with(
        anything,
        hash_including(worker_count: 2)
      ).and_call_original

      allow(client).to receive(:generate).and_return('summary')

      Commiti::DiffSummarizer.summarize_if_needed(large_diff, client: client, model: 'gemma', worker_count: 2)
    end

    it 'returns deterministic fallback when summarization times out' do
      big_diff = <<~DIFF + ("+x\n" * 9000)
        diff --git a/lib/a.rb b/lib/a.rb
        index 111..222 100644
        --- a/lib/a.rb
        +++ b/lib/a.rb
        @@ -1 +1,2 @@
      DIFF

      allow(Commiti::DiffSummarizer::BatchRunner).to receive(:summarize_chunks).and_raise(Net::ReadTimeout.new)

      result = described_class.summarize_if_needed(
        big_diff,
        client: client,
        chunks: [{ path: 'lib/a.rb', diff: big_diff }]
      )

      expect(result[:summarized]).to be(true)
      expect(result[:fallback_reason]).to include('Summarization timed out')
      expect(result[:content]).to include('### Diff Overview')
      expect(result[:content]).to include('### lib/a.rb')
    end
  end

  describe '.mechanical_summary' do
    it 'counts additions, deletions, and hunks' do
      diff = "+added line\n-removed line\n@@ -1 +1 @@\n"
      result = Commiti::DiffSummarizer::FallbackBuilder.mechanical_summary(diff)
      expect(result).to include('1 additions')
      expect(result).to include('1 deletions')
      expect(result).to include('1 hunk')
    end
  end

  describe '.summarize_chunks' do
    it 'batches large chunks and preserves chunk order' do
      large_diff = <<~DIFF + ("+x\n" * 1200)
        diff --git a/lib/a.rb b/lib/a.rb
        @@ -1 +1,2 @@
      DIFF
      larger_diff = <<~DIFF + ("+y\n" * 1200)
        diff --git a/lib/b.rb b/lib/b.rb
        @@ -1 +1,2 @@
      DIFF
      largest_diff = <<~DIFF + ("+z\n" * 1200)
        diff --git a/lib/c.rb b/lib/c.rb
        @@ -1 +1,2 @@
      DIFF

      chunks = [
        { path: 'lib/a.rb', diff: large_diff },
        { path: 'lib/b.rb', diff: larger_diff },
        { path: 'lib/c.rb', diff: largest_diff }
      ]

      client = Class.new do
        attr_reader :thread_ids, :call_count

        def initialize
          @thread_ids = []
          @call_count = 0
          @mutex = Mutex.new
        end

        def generate(user:, **_kwargs)
          sleep 0.05
          paths = user.scan(/^### (.+)$/).flatten
          @mutex.synchronize do
            @thread_ids << Thread.current.object_id
            @call_count += 1
          end
          if paths.length > 1
            paths.map { |path| "### #{path}\n- summary for #{path}" }.join("\n\n")
          else
            path = user[%r{diff --git a/(.+?) b/}, 1]
            "- summary for #{path}"
          end
        end
      end.new

      summaries = Commiti::DiffSummarizer::BatchRunner.summarize_chunks(chunks, client: client, model: Commiti::GoogleClient::DEFAULT_MODEL)

      expect(summaries[0]).to include("### lib/a.rb\n- summary for lib/a.rb")
      expect(summaries[1]).to include("### lib/b.rb\n- summary for lib/b.rb")
      expect(summaries[2]).to include("### lib/c.rb\n- summary for lib/c.rb")
      expect(client.call_count).to be < chunks.length
    end
  end
end
