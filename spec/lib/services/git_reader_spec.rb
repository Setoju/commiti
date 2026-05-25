# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::GitReader do
  describe '.split_by_file' do
    it 'splits a diff into file chunks' do
      diff = <<~DIFF
        diff --git a/lib/a.rb b/lib/a.rb
        index 111..222 100644
        --- a/lib/a.rb
        +++ b/lib/a.rb
        @@ -1 +1 @@
        -old
        +new
        diff --git a/lib/b.rb b/lib/b.rb
        index 333..444 100644
        --- a/lib/b.rb
        +++ b/lib/b.rb
        @@ -1 +1 @@
        -before
        +after
      DIFF

      chunks = described_class.split_by_file(diff)

      expect(chunks.length).to eq(2)
      expect(chunks[0][:path]).to eq('lib/a.rb')
      expect(chunks[1][:path]).to eq('lib/b.rb')
      expect(chunks[0][:lines].first).to start_with('diff --git')
    end
  end

  describe '.clip_diff_context' do
    it 'returns the original diff when it is under the byte limit' do
      diff = "diff --git a/a.rb b/a.rb\n@@ -1 +1 @@\n-old\n+new\n"

      clipped = described_class.clip_diff_context(diff, max_bytes: 500)

      expect(clipped).to eq(diff)
    end

    it 'clips by file and hunk while preserving structure and notice' do
      long_hunk = (1..400).map { |i| "+line #{i}" }.join("\n")
      diff = <<~DIFF
        diff --git a/a.rb b/a.rb
        index 111..222 100644
        --- a/a.rb
        +++ b/a.rb
        @@ -1 +1,400 @@
        #{long_hunk}
        diff --git a/b.rb b/b.rb
        index 333..444 100644
        --- a/b.rb
        +++ b/b.rb
        @@ -1 +1 @@
        -before
        +after
      DIFF

      clipped = described_class.clip_diff_context(diff, max_bytes: 500)

      expect(clipped.bytesize).to be <= 500
      expect(clipped).to include('diff --git a/a.rb b/a.rb')
      expect(clipped).to include('@@ -1 +1,400 @@')
      expect(clipped).to include(described_class::TRUNCATION_NOTICE.strip)
    end
  end

  describe '.branch_diff' do
    it 'rejects invalid branch names before running git' do
      expect do
        described_class.branch_diff(base_branch: 'main; rm -rf /')
      end.to raise_error('Invalid branch name.')
    end
  end

  describe '.commits_in_range' do
    it 'rejects invalid ranges before running git' do
      expect do
        described_class.commits_in_range(range: 'main; rm -rf /')
      end.to raise_error('Invalid changelog range.')
    end

    it 'parses commit log entries' do
      log_output = [
        "aaaaaaaa#{Commiti::GitReader::LOG_FIELD_SEPARATOR}feat: add widget#{Commiti::GitReader::LOG_FIELD_SEPARATOR}body",
        Commiti::GitReader::LOG_RECORD_SEPARATOR,
        "bbbbbbbb#{Commiti::GitReader::LOG_FIELD_SEPARATOR}fix: patch#{Commiti::GitReader::LOG_FIELD_SEPARATOR}",
        Commiti::GitReader::LOG_RECORD_SEPARATOR
      ].join

      allow(Open3).to receive(:capture3).and_return([log_output, '', instance_double(Process::Status, success?: true)])

      commits = described_class.commits_in_range(range: 'v1.2.0..HEAD')

      expect(commits.length).to eq(2)
      expect(commits[0][:sha]).to eq('aaaaaaaa')
      expect(commits[0][:subject]).to eq('feat: add widget')
      expect(commits[1][:sha]).to eq('bbbbbbbb')
      expect(commits[1][:subject]).to eq('fix: patch')
    end
  end
end
