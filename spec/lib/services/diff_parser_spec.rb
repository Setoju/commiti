# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::DiffParser do
  describe '.split_by_file_lines' do
    it 'splits diff blocks into path and line arrays' do
      diff = <<~DIFF
        diff --git a/lib/a.rb b/lib/a.rb
        @@ -1 +1 @@
        -old
        +new
        diff --git a/docs/readme.md b/docs/readme.md
        @@ -1 +1 @@
        -before
        +after
      DIFF

      chunks = described_class.split_by_file_lines(diff)

      expect(chunks.length).to eq(2)
      expect(chunks[0][:path]).to eq('lib/a.rb')
      expect(chunks[1][:path]).to eq('docs/readme.md')
      expect(chunks[0][:lines].first).to start_with('diff --git')
    end
  end

  describe '.metadata_from_line_chunks' do
    it 'derives file metadata and docs-only flag' do
      chunks = [
        { path: 'docs/guide.md', lines: [] },
        { path: 'README.md', lines: [] }
      ]

      metadata = described_class.metadata_from_line_chunks(chunks)

      expect(metadata[:total_files]).to eq(2)
      expect(metadata[:files]).to eq(['docs/guide.md', 'README.md'])
      expect(metadata[:docs_only]).to be(true)
    end

    it 'marks docs_only false when non-documentation files are present' do
      chunks = [
        { path: 'docs/guide.md', lines: [] },
        { path: 'lib/a.rb', lines: [] }
      ]

      metadata = described_class.metadata_from_line_chunks(chunks)

      expect(metadata[:docs_only]).to be(false)
    end
  end

  describe '.clip' do
    it 'returns the diff unchanged when it is within the byte limit' do
      diff = 'a' * 100
      clipped = described_class.clip(diff, max_bytes: 500)
      expect(clipped).to eq(diff)
    end

    it 'clips by file and hunk while preserving structure and notice' do
      header = "diff --git a/a.rb b/a.rb\nindex 000..111 100644\n--- a/a.rb\n+++ b/a.rb\n"
      hunk   = "@@ -1 +1,400 @@\n" + ("+line\n" * 400)
      diff   = header + hunk

      clipped = described_class.clip(diff, max_bytes: 500)

      expect(clipped.bytesize).to be <= 500
      expect(clipped).to include('diff --git a/a.rb b/a.rb')
      expect(clipped).to include('@@ -1 +1,400 @@')
      expect(clipped).to include(described_class::TRUNCATION_NOTICE.strip)
    end
  end
end
