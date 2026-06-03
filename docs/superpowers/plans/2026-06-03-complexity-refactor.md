# Complexity Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove thin wrappers and redundant layers from the commiti gem, reducing 46 source files to 39 with no behavior change.

**Architecture:** Each task deletes one file by moving its content into its single caller, then migrates the corresponding spec. Tasks are ordered lowest-coupling-first so each one is independently green.

**Tech Stack:** Ruby gem, RSpec (`bundle exec rspec`), no external services needed for tests.

---

## File Map

**Deleted (source):** `lib/services/scope_inferrer.rb`, `lib/services/changelog_builder.rb`, `lib/flows/flow_base.rb`, `lib/services/git/commit/auto_split_coordinator.rb`, `lib/services/message_generation/commit_normalizer.rb`, `lib/services/message_generation/message_cleaner.rb`, `lib/services/message_generation/message_validator.rb`

**Deleted (spec):** `spec/lib/services/scope_inferrer_spec.rb`, `spec/lib/services/changelog_builder_spec.rb`, `spec/lib/flows/flow_base_spec.rb`, `spec/lib/services/git/commit/auto_split_coordinator_spec.rb`, `spec/lib/services/message_generation/commit_normalizer_spec.rb`, `spec/lib/services/message_generation/message_cleaner_spec.rb`, `spec/lib/services/message_generation/message_validator_spec.rb`

**Modified (absorbs deleted content):** `lib/services/flow_context_builder.rb`, `lib/flows/changelog_flow.rb`, `lib/flows/base_flow.rb`, `lib/services/git/diff_parser.rb`, `lib/services/message_generator.rb`, `lib/flows/commit_flow.rb`

**Modified (cleanup):** `lib/commiti.rb`, `lib/services/git/git_reader.rb`, `lib/services/style_analyzer.rb`, `lib/services/helpers/config_loader.rb`

---

## Task 1: Inline ScopeInferrer into FlowContextBuilder

**Files:**
- Modify: `lib/services/flow_context_builder.rb`
- Modify: `spec/lib/services/flow_context_builder_spec.rb`
- Modify: `lib/commiti.rb`
- Delete: `lib/services/scope_inferrer.rb`
- Delete: `spec/lib/services/scope_inferrer_spec.rb`

- [ ] **Step 1: Run baseline**

```bash
bundle exec rspec spec/lib/services/scope_inferrer_spec.rb spec/lib/services/flow_context_builder_spec.rb
```
Expected: all pass.

- [ ] **Step 2: Rewrite `lib/services/flow_context_builder.rb`**

Remove the `require_relative 'scope_inferrer'` line and expand the private `infer_scope` method to contain all logic from `ScopeInferrer`. Add `FALLBACK_SCOPE_MAP`, `infer_scope_for_files`, `match_common_scope`, and `fallback_scope` as private class methods:

```ruby
# frozen_string_literal: true

module Commiti
  module FlowContextBuilder
    FALLBACK_SCOPE_MAP = {
      'auth' => 'auth',
      'authentication' => 'auth',
      'sessions' => 'auth',
      'api' => 'api',
      'controllers' => 'api',
      'models' => 'db',
      'db' => 'db',
      'migrations' => 'db',
      'spec' => 'test',
      'test' => 'test',
      'config' => 'config'
    }.freeze

    def self.build(flow_type:, diff:, client:, run_stage:, model:, text_generation_config: nil, worker_count: nil,
                   style_profile: nil, inferred_scope: nil)
      line_chunks = Commiti::DiffParser.split_by_file_lines(diff)
      diff_metadata = Commiti::DiffParser.metadata_from_line_chunks(line_chunks)
      change_groups = Commiti::ChangeGrouping.group(line_chunks)
      inferred_scope ||= infer_scope(flow_type, diff_metadata, style_profile)

      summarized_result = run_stage.call('Preparing diff for AI model') do
        Commiti::DiffSummarizer.summarize_if_needed(
          diff,
          client: client,
          model: model,
          chunks: summary_chunks(line_chunks),
          worker_count: worker_count
        )
      end

      prompt = Commiti::PromptBuilder.build(
        type: flow_type,
        diff: summarized_result[:content],
        summarized: summarized_result[:summarized],
        raw_diff: diff,
        diff_metadata: diff_metadata,
        style_config: text_generation_config,
        style_profile: style_profile,
        inferred_scope: inferred_scope
      )

      {
        diff_metadata: diff_metadata,
        change_groups: change_groups,
        summarized_result: summarized_result,
        prompt: prompt
      }
    end

    def self.summary_chunks(line_chunks)
      line_chunks.map { |chunk| { path: chunk[:path], diff: chunk[:lines].join } }
    end
    private_class_method :summary_chunks

    def self.infer_scope(flow_type, diff_metadata, style_profile)
      return nil unless flow_type == :commit
      return nil unless style_profile

      infer_scope_for_files(
        files: Array(diff_metadata&.dig(:files)),
        common_scopes: style_profile.common_scopes
      )
    end
    private_class_method :infer_scope

    def self.infer_scope_for_files(files:, common_scopes:)
      return nil if files.nil? || files.empty?

      normalized_common = Array(common_scopes).map { |scope| scope.to_s.strip.downcase }.reject(&:empty?)
      inferred = Array(files).filter_map do |file|
        segments = file.to_s.split('/').reject(&:empty?)
        next if segments.empty?

        match_common_scope(segments, normalized_common) || fallback_scope(segments)
      end

      inferred = inferred.compact.uniq
      return nil if inferred.empty?
      return inferred.first if inferred.length == 1

      nil
    rescue StandardError
      nil
    end
    private_class_method :infer_scope_for_files

    def self.match_common_scope(segments, common_scopes)
      return nil if common_scopes.empty?

      segments.each do |segment|
        normalized = segment.to_s.downcase
        return normalized if common_scopes.include?(normalized)
      end
      nil
    end
    private_class_method :match_common_scope

    def self.fallback_scope(segments)
      segments.each_with_index do |segment, index|
        normalized = segment.to_s.downcase
        return FALLBACK_SCOPE_MAP[normalized] if FALLBACK_SCOPE_MAP.key?(normalized)

        next unless normalized == 'lib'

        next_segment = segments[index + 1].to_s
        return nil if next_segment.empty?

        base = File.basename(next_segment, File.extname(next_segment)).downcase
        return FALLBACK_SCOPE_MAP.fetch(base, base)
      end
      nil
    end
    private_class_method :fallback_scope
  end
end
```

- [ ] **Step 3: Migrate scope inferrer tests into `spec/lib/services/flow_context_builder_spec.rb`**

Add this block inside the existing `RSpec.describe Commiti::FlowContextBuilder do` block:

```ruby
describe 'scope inference (private)' do
  it 'matches common scopes from path segments' do
    result = described_class.send(:infer_scope_for_files,
      files: ['app/services/auth/token_service.rb'],
      common_scopes: %w[auth api]
    )
    expect(result).to eq('auth')
  end

  it 'falls back to built-in mappings when no common scope matches' do
    result = described_class.send(:infer_scope_for_files,
      files: ['app/controllers/sessions_controller.rb'],
      common_scopes: []
    )
    expect(result).to eq('api')
  end

  it 'returns nil when inferred scopes are mixed' do
    result = described_class.send(:infer_scope_for_files,
      files: ['app/controllers/users_controller.rb', 'app/models/user.rb'],
      common_scopes: []
    )
    expect(result).to be_nil
  end

  it 'infers scope from lib namespace when available' do
    result = described_class.send(:infer_scope_for_files,
      files: ['lib/payments/processor.rb'],
      common_scopes: []
    )
    expect(result).to eq('payments')
  end

  it 'applies FALLBACK_SCOPE_MAP to lib/* next segments' do
    result = described_class.send(:infer_scope_for_files,
      files: ['lib/controllers/users_controller.rb'],
      common_scopes: []
    )
    expect(result).to eq('api')
  end

  it 'returns nil when no files are provided' do
    result = described_class.send(:infer_scope_for_files,
      files: [],
      common_scopes: %w[auth]
    )
    expect(result).to be_nil
  end
end
```

- [ ] **Step 4: Remove the `scope_inferrer` require from `lib/commiti.rb`**

Delete this line:
```ruby
require_relative 'services/scope_inferrer'
```

- [ ] **Step 5: Delete the old files**

```bash
rm lib/services/scope_inferrer.rb
rm spec/lib/services/scope_inferrer_spec.rb
```

- [ ] **Step 6: Run tests**

```bash
bundle exec rspec spec/lib/services/flow_context_builder_spec.rb
```
Expected: all pass including the new scope inference block.

```bash
bundle exec rspec
```
Expected: full suite green.

- [ ] **Step 7: Commit**

```bash
git add -p
git commit -m "refactor: inline ScopeInferrer into FlowContextBuilder"
```

---

## Task 2: Inline ChangelogBuilder into ChangelogFlow

**Files:**
- Modify: `lib/flows/changelog_flow.rb`
- Create: `spec/lib/flows/changelog_flow_spec.rb`
- Modify: `lib/commiti.rb`
- Delete: `lib/services/changelog_builder.rb`
- Delete: `spec/lib/services/changelog_builder_spec.rb`

- [ ] **Step 1: Run baseline**

```bash
bundle exec rspec spec/lib/services/changelog_builder_spec.rb
```
Expected: all pass.

- [ ] **Step 2: Rewrite `lib/flows/changelog_flow.rb`**

Move `TYPE_TITLES`, `TYPE_PATTERN`, and all three methods into the flow as private instance methods:

```ruby
# frozen_string_literal: true

module Commiti
  module Flows
    class ChangelogFlow < FlowBase
      TYPE_TITLES = {
        'feat' => 'Features',
        'fix' => 'Fixes',
        'docs' => 'Documentation',
        'perf' => 'Performance',
        'refactor' => 'Refactors',
        'test' => 'Tests',
        'chore' => 'Chores',
        'ci' => 'CI',
        'build' => 'Build',
        'style' => 'Style',
        'revert' => 'Reverts'
      }.freeze

      TYPE_PATTERN = /\A(?<type>[a-zA-Z]+)(?<scope>\([^)]+\))?(?<breaking>!)?:\s+(?<subject>.+)\z/.freeze

      def run
        range = options[:range].to_s.strip
        raise 'Changelog range is required. Use --range v1.2.0..HEAD.' if range.empty?

        commits = run_stage('Collecting commits') { Commiti::GitReader.commits_in_range(range: range) }
        changelog = run_stage('Formatting changelog') { build_changelog(commits, range: range) }
        Commiti::MessagePresenter.print_message(changelog, title: 'Changelog')
      end

      private

      def build_changelog(commits, range:)
        groups = Hash.new { |hash, key| hash[key] = [] }

        commits.each do |commit|
          subject = commit[:subject].to_s.strip
          next if subject.empty?
          next if subject.start_with?('Merge ')

          parsed = parse_subject(subject)
          group_title = TYPE_TITLES.fetch(parsed[:type], 'Other')
          groups[group_title] << format_entry(commit, parsed)
        end

        ordered_titles = TYPE_TITLES.values + ['Other']
        lines = ["# Changelog (#{range})", '']
        ordered_titles.each do |title|
          entries = groups[title]
          next if entries.empty?

          lines << "## #{title}"
          lines.concat(entries.map { |entry| "- #{entry}" })
          lines << ''
        end

        raise 'No commits found in range.' if lines.length <= 2

        lines.join("\n").rstrip
      end

      def parse_subject(subject)
        match = subject.match(TYPE_PATTERN)
        return { type: 'other', scope: nil, subject: subject, breaking: false } unless match

        {
          type: match[:type].downcase,
          scope: match[:scope]&.tr('()', ''),
          subject: match[:subject].to_s.strip,
          breaking: !match[:breaking].nil?
        }
      end

      def format_entry(commit, parsed)
        short_sha = commit[:sha].to_s[0, 7]
        label = parsed[:subject]
        label = "#{parsed[:scope]}: #{label}" if parsed[:scope]
        label = "BREAKING: #{label}" if parsed[:breaking]
        "#{label} (#{short_sha})"
      end
    end
  end
end
```

- [ ] **Step 3: Create `spec/lib/flows/changelog_flow_spec.rb`**

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::Flows::ChangelogFlow do
  let(:flow) { described_class.new(options: { range: 'v1.2.0..HEAD' }) }

  before do
    allow(Commiti::ConfigLoader).to receive(:load).and_return({})
    allow(Commiti::Spinner).to receive(:run) { |_label, &block| block.call }
    allow(Commiti::MessagePresenter).to receive(:print_message)
  end

  describe '#run' do
    it 'groups commits by conventional type and formats entries' do
      commits = [
        { sha: 'aaaaaaaa', subject: 'feat(api): add widget', body: '' },
        { sha: 'bbbbbbbb', subject: 'fix: patch issue', body: '' },
        { sha: 'cccccccc', subject: 'docs: update readme', body: '' },
        { sha: 'dddddddd', subject: 'misc cleanup', body: '' }
      ]
      allow(Commiti::GitReader).to receive(:commits_in_range).and_return(commits)

      expect(Commiti::MessagePresenter).to receive(:print_message) do |changelog, **|
        expect(changelog).to include('# Changelog (v1.2.0..HEAD)')
        expect(changelog).to include('## Features')
        expect(changelog).to include('- api: add widget (aaaaaaa)')
        expect(changelog).to include('## Fixes')
        expect(changelog).to include('- patch issue (bbbbbbb)')
        expect(changelog).to include('## Documentation')
        expect(changelog).to include('- update readme (ccccccc)')
        expect(changelog).to include('## Other')
        expect(changelog).to include('- misc cleanup (ddddddd)')
      end

      flow.run
    end

    it 'raises when no commits are present' do
      allow(Commiti::GitReader).to receive(:commits_in_range).and_return([])

      expect { flow.run }.to raise_error('No commits found in range.')
    end

    it 'raises when range is blank' do
      flow_no_range = described_class.new(options: { range: '' })
      expect { flow_no_range.run }.to raise_error('Changelog range is required. Use --range v1.2.0..HEAD.')
    end
  end
end
```

- [ ] **Step 4: Remove the `changelog_builder` require from `lib/commiti.rb`**

Delete this line:
```ruby
require_relative 'services/changelog_builder'
```

- [ ] **Step 5: Delete the old files**

```bash
rm lib/services/changelog_builder.rb
rm spec/lib/services/changelog_builder_spec.rb
```

- [ ] **Step 6: Run tests**

```bash
bundle exec rspec spec/lib/flows/changelog_flow_spec.rb
```
Expected: all pass.

```bash
bundle exec rspec
```
Expected: full suite green.

- [ ] **Step 7: Commit**

```bash
git add -p
git commit -m "refactor: inline ChangelogBuilder into ChangelogFlow"
```

---

## Task 3: Merge FlowBase into BaseFlow

**Files:**
- Modify: `lib/flows/base_flow.rb`
- Modify: `lib/flows/changelog_flow.rb` (parent class change)
- Modify: `spec/lib/flows/base_flow_spec.rb`
- Modify: `lib/commiti.rb`
- Delete: `lib/flows/flow_base.rb`
- Delete: `spec/lib/flows/flow_base_spec.rb`

Note: `InitFlow` and `DoctorFlow` do NOT inherit from `FlowBase` — they are standalone classes and need no changes.

- [ ] **Step 1: Run baseline**

```bash
bundle exec rspec spec/lib/flows/flow_base_spec.rb spec/lib/flows/base_flow_spec.rb
```
Expected: all pass.

- [ ] **Step 2: Rewrite `lib/flows/base_flow.rb`**

Remove the `< FlowBase` inheritance and inline the two methods from `FlowBase` (`initialize` and `run_stage`) directly:

```ruby
# frozen_string_literal: true

module Commiti
  module Flows
    class BaseFlow
      def initialize(options:)
        @options = Commiti::ConfigLoader.load.merge(options || {})
      end

      def run
        prepare!
        diff = collect_diff
        client = Commiti::ClientFactory.build(config: options)
        selected_model = options[:model]
        style_profile = style_profile_for_flow
        context = Commiti::FlowContextBuilder.build(
          flow_type: flow_type,
          diff: diff,
          client: client,
          run_stage: method(:run_stage),
          model: selected_model,
          text_generation_config: options[:text_generation],
          style_profile: style_profile,
          worker_count: options[:diff_summary_workers]
        )
        Commiti::MessagePresenter.print_summarization_notice(context[:summarized_result])

        candidates = generate_candidates(
          client: client,
          prompt: context[:prompt],
          diff_metadata: context[:diff_metadata],
          model: selected_model
        )
        message = select_message(candidates)

        maybe_copy_to_clipboard(message)
        finalize(message)
      end

      private

      attr_reader :options

      def run_stage(message, &)
        Commiti::Spinner.run(message, &)
      end

      def prepare!; end

      def collect_diff
        raise NotImplementedError, "#{self.class} must implement #collect_diff"
      end

      def flow_type
        raise NotImplementedError, "#{self.class} must implement #flow_type"
      end

      def finalize(_message); end

      def generate_with_quality_check(client:, prompt:, diff_metadata:, model:)
        message_generator.generate_with_quality_check(
          client: client,
          prompt: prompt,
          diff_metadata: diff_metadata,
          model: model
        )
      end

      def generate_candidates(client:, prompt:, diff_metadata:, model:)
        count = options[:candidates].to_i
        message_generator.generate_candidates(
          client: client,
          prompt: prompt,
          diff_metadata: diff_metadata,
          count: count,
          model: model
        )
      end

      def select_message(candidates)
        Commiti::MessagePresenter.select_message(candidates)
      end

      def print_message(message)
        Commiti::MessagePresenter.print_message(message)
      end

      def maybe_copy_to_clipboard(message)
        Commiti::MessagePresenter.maybe_copy_to_clipboard(
          message,
          no_copy: options[:no_copy],
          run_stage: method(:run_stage)
        )
      end

      def message_generator
        @message_generator ||= Commiti::MessageGenerator.new(
          flow_type: flow_type,
          run_stage: method(:run_stage),
          text_generation_config: options[:text_generation]
        )
      end

      def style_profile_for_flow
        return nil unless flow_type == :commit
        return options[:style_snapshot] if options[:style_snapshot]
        return nil if options[:style_learning] == false

        Commiti::StyleAnalyzer.analyze(lookback: options[:style_lookback])
      end
    end
  end
end
```

- [ ] **Step 3: Update `ChangelogFlow` parent class**

In `lib/flows/changelog_flow.rb`, change `< FlowBase` to `< BaseFlow`:

```ruby
class ChangelogFlow < BaseFlow
```

- [ ] **Step 4: Verify `base_flow_spec.rb` already covers the `flow_base_spec.rb` scenarios**

`FlowBase` had two behaviors: `initialize` merges `ConfigLoader.load` with the passed options hash, and `run_stage` delegates to `Spinner.run`. Open `spec/lib/flows/flow_base_spec.rb` and confirm both behaviors are already covered in `spec/lib/flows/base_flow_spec.rb` (they will be, since `BaseFlow < FlowBase` meant every `BaseFlow` instance went through those methods). If a test in `flow_base_spec.rb` has no equivalent in `base_flow_spec.rb`, copy it across before deleting.

- [ ] **Step 5: Remove the `flow_base` require from `lib/commiti.rb`**

Delete this line:
```ruby
require_relative 'flows/flow_base'
```

- [ ] **Step 6: Delete the old files**

```bash
rm lib/flows/flow_base.rb
rm spec/lib/flows/flow_base_spec.rb
```

- [ ] **Step 7: Run tests**

```bash
bundle exec rspec spec/lib/flows/base_flow_spec.rb spec/lib/flows/changelog_flow_spec.rb
```
Expected: all pass.

```bash
bundle exec rspec
```
Expected: full suite green.

- [ ] **Step 8: Commit**

```bash
git add -p
git commit -m "refactor: merge FlowBase into BaseFlow"
```

---

## Task 4: Move diff clipping from GitReader to DiffParser

**Files:**
- Modify: `lib/services/git/diff_parser.rb`
- Modify: `lib/services/git/git_reader.rb`
- Modify: `spec/lib/services/diff_parser_spec.rb` (or create if it doesn't exist)
- Modify: `spec/lib/services/git_reader_spec.rb`

- [ ] **Step 1: Run baseline**

```bash
bundle exec rspec spec/lib/services/git_reader_spec.rb
```
Expected: all pass including the `clip_diff_context` tests.

- [ ] **Step 2: Add `clip` and clipping helpers to `lib/services/git/diff_parser.rb`**

Append to the end of `DiffParser` (before the closing `end`):

```ruby
MAX_DIFF_BYTES = 50_000
TRUNCATION_NOTICE = "\n# ... diff clipped by Commiti to preserve context under size limit\n"

def self.clip(diff, max_bytes: MAX_DIFF_BYTES)
  return diff if diff.bytesize <= max_bytes

  chunks = split_by_file_lines(diff)
  clipped = if chunks.empty?
              diff.byteslice(0, max_bytes)
            else
              clip_chunks(chunks, max_bytes: max_bytes)
            end

  append_notice(clipped, max_bytes: max_bytes)
end

def self.clip_chunks(chunks, max_bytes:)
  output = +''

  chunks.each do |chunk|
    remaining = max_bytes - output.bytesize
    break if remaining <= 0

    chunk_text = chunk[:lines].join
    if chunk_text.bytesize <= remaining
      output << chunk_text
      next
    end

    output << clip_single_chunk(chunk[:lines], max_bytes: remaining)
    break
  end

  if output.empty?
    first_chunk_text = chunks.first[:lines].join
    return first_chunk_text.byteslice(0, max_bytes)
  end

  output
end
private_class_method :clip_chunks

def self.clip_single_chunk(lines, max_bytes:)
  output = +''
  return output if max_bytes <= 0

  header_lines, hunks = partition_chunk_lines(lines)
  append_lines_with_limit(output, header_lines, max_bytes: max_bytes)
  return output if hunks.empty?

  append_hunks_with_limit(output, hunks, max_bytes: max_bytes)
  output
end
private_class_method :clip_single_chunk

def self.partition_chunk_lines(lines)
  header_lines = []
  hunks = []
  current_hunk = nil

  lines.each do |line|
    if line.start_with?('@@')
      current_hunk = [line]
      hunks << current_hunk
    elsif current_hunk
      current_hunk << line
    else
      header_lines << line
    end
  end

  [header_lines, hunks]
end
private_class_method :partition_chunk_lines

def self.append_lines_with_limit(output, lines, max_bytes:)
  lines.each do |line|
    break if output.bytesize + line.bytesize > max_bytes

    output << line
  end
end
private_class_method :append_lines_with_limit

def self.append_hunks_with_limit(output, hunks, max_bytes:)
  hunks.each do |hunk|
    hunk_text = hunk.join
    if output.bytesize + hunk_text.bytesize <= max_bytes
      output << hunk_text
      next
    end

    append_partial_hunk(output, hunk, max_bytes: max_bytes)
    break
  end
end
private_class_method :append_hunks_with_limit

def self.append_partial_hunk(output, hunk, max_bytes:)
  hunk_header = hunk.first
  return if output.bytesize + hunk_header.bytesize > max_bytes

  output << hunk_header
  append_lines_with_limit(output, hunk[1..].to_a, max_bytes: max_bytes)
end
private_class_method :append_partial_hunk

def self.append_notice(clipped_diff, max_bytes:)
  safe_clipped = clipped_diff.to_s
  return safe_clipped if safe_clipped.bytesize >= max_bytes && max_bytes <= TRUNCATION_NOTICE.bytesize

  return safe_clipped + TRUNCATION_NOTICE if safe_clipped.bytesize + TRUNCATION_NOTICE.bytesize <= max_bytes

  available = max_bytes - TRUNCATION_NOTICE.bytesize
  return safe_clipped.byteslice(0, max_bytes) if available <= 0

  safe_clipped.byteslice(0, available) + TRUNCATION_NOTICE
end
private_class_method :append_notice
```

- [ ] **Step 3: Update `lib/services/git/git_reader.rb`**

Remove the `MAX_DIFF_BYTES` and `TRUNCATION_NOTICE` constants. Replace calls to the internal clipping methods with `Commiti::DiffParser.clip(...)`. Remove all the `clip_*`, `partition_chunk_lines`, `append_*`, and `split_by_file` private methods:

```ruby
# frozen_string_literal: true

require 'open3'
require_relative 'diff_parser'

module Commiti
  module GitReader
    def self.staged_diff
      diff, status = Open3.capture2('git', 'diff', '--cached', '-U0')
      raise 'Failed to read staged diff.' unless status.success?
      raise 'No staged changes. Run `git add` first.' if diff.strip.empty?

      filtered_diff = filter_diff_noise(diff)
      Commiti::DiffParser.clip(filtered_diff)
    end

    def self.branch_diff(base_branch: 'main')
      raise 'Invalid branch name.' unless base_branch.match?(%r{\A[a-zA-Z0-9_\-./]+\z})

      diff, status = Open3.capture2('git', 'diff', '-U0', "#{base_branch}...HEAD")
      raise "Failed to read branch diff against '#{base_branch}'." unless status.success?
      raise "No diff found against '#{base_branch}'." if diff.strip.empty?

      filtered_diff = filter_diff_noise(diff)
      Commiti::DiffParser.clip(filtered_diff)
    end

    def self.recent_commits(count: 10)
      out, = Open3.capture2('git', 'log', '--oneline', "-#{count}")
      out
    end

    LOG_RECORD_SEPARATOR = "\x1e"
    LOG_FIELD_SEPARATOR = "\x1f"

    def self.recent_commit_messages(n: 50)
      format = ['%s', '%b'].join(LOG_FIELD_SEPARATOR) + LOG_RECORD_SEPARATOR
      output, err, status = Open3.capture3(
        'git',
        'log',
        '--no-color',
        '--no-merges',
        "--pretty=format:#{format}",
        '-n',
        n.to_i.to_s
      )
      raise "Failed to read recent git commits: #{err.strip.empty? ? output.strip : err.strip}" unless status.success?
      return [] if output.to_s.strip.empty?

      output.split(LOG_RECORD_SEPARATOR).filter_map do |record|
        next if record.strip.empty?

        subject, body = record.split(LOG_FIELD_SEPARATOR, 2)
        {
          subject: subject.to_s.strip,
          body: body.to_s
        }
      end
    end

    def self.remote_url(remote: 'origin')
      output, status = Open3.capture2('git', 'remote', 'get-url', remote)
      status.success? ? output.strip : nil
    rescue StandardError
      nil
    end

    def self.commits_in_range(range:)
      raise 'Invalid changelog range.' unless valid_range?(range)

      format = ['%H', '%s', '%b'].join(LOG_FIELD_SEPARATOR) + LOG_RECORD_SEPARATOR
      out, err, status = Open3.capture3('git', 'log', '--no-color', "--pretty=format:#{format}", range.to_s)
      raise "Failed to read git log for range '#{range}': #{err.strip.empty? ? out.strip : err.strip}" unless status.success?
      return [] if out.to_s.strip.empty?

      out.split(LOG_RECORD_SEPARATOR).filter_map do |record|
        next if record.strip.empty?

        sha, subject, body = record.split(LOG_FIELD_SEPARATOR, 3)
        {
          sha: sha.to_s.strip,
          subject: subject.to_s.strip,
          body: body.to_s
        }
      end
    end

    def self.valid_range?(range)
      range.to_s.match?(%r{\A[a-zA-Z0-9_\-./]+(\.\.\.?[a-zA-Z0-9_\-./]+)\z})
    end
    private_class_method :valid_range?

    LOCKFILE_PATTERNS = [
      /Gemfile\.lock/,
      /package-lock\.json/,
      /yarn\.lock/,
      /pnpm-lock\.yaml/,
      /composer\.lock/,
      /mix\.lock/,
      /Cargo\.lock/,
      /Pipfile\.lock/
    ].freeze

    def self.filter_diff_noise(diff)
      filtered_lines = []
      skip_chunk = false

      diff.each_line do |line|
        if line.start_with?('diff --git')
          path = extract_path_from_diff_header(line)
          is_lockfile = LOCKFILE_PATTERNS.any? { |pattern| path.match?(pattern) }
          is_binary_diff_header = line.include?('Binary files')

          if is_lockfile || is_binary_diff_header
            skip_chunk = true
            next
          else
            skip_chunk = false
          end
        end

        filtered_lines << line unless skip_chunk
      end
      filtered_lines.join
    end
    private_class_method :filter_diff_noise

    def self.extract_path_from_diff_header(line)
      match = line.chomp.match(%r{\Adiff --git a/(.+) b/(.+)\z})
      match ? match[2].strip : 'unknown'
    end
    private_class_method :extract_path_from_diff_header
  end
end
```

- [ ] **Step 4: Migrate clip tests from `spec/lib/services/git_reader_spec.rb` to `spec/lib/services/diff_parser_spec.rb`**

In `git_reader_spec.rb`, find the `describe '.clip_diff_context'` block and move it to `diff_parser_spec.rb`. Update `described_class` references — they now refer to `Commiti::DiffParser`. Rename `clip_diff_context` to `clip`. Update `described_class::TRUNCATION_NOTICE` references (still works since the constant is now on `DiffParser`):

```ruby
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
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/lib/services/diff_parser_spec.rb spec/lib/services/git_reader_spec.rb
```
Expected: all pass (git_reader_spec no longer has the clip tests; diff_parser_spec has them).

```bash
bundle exec rspec
```
Expected: full suite green.

- [ ] **Step 6: Commit**

```bash
git add -p
git commit -m "refactor: move diff clipping from GitReader to DiffParser"
```

---

## Task 5: Inline message_generation/* into MessageGenerator

**Files:**
- Modify: `lib/services/message_generator.rb`
- Modify: `spec/lib/services/message_generator_spec.rb`
- Modify: `lib/commiti.rb`
- Delete: `lib/services/message_generation/commit_normalizer.rb`
- Delete: `lib/services/message_generation/message_cleaner.rb`
- Delete: `lib/services/message_generation/message_validator.rb`
- Delete: `spec/lib/services/message_generation/commit_normalizer_spec.rb`
- Delete: `spec/lib/services/message_generation/message_cleaner_spec.rb`
- Delete: `spec/lib/services/message_generation/message_validator_spec.rb`

- [ ] **Step 1: Run baseline**

```bash
bundle exec rspec spec/lib/services/message_generator_spec.rb \
  spec/lib/services/message_generation/commit_normalizer_spec.rb \
  spec/lib/services/message_generation/message_cleaner_spec.rb \
  spec/lib/services/message_generation/message_validator_spec.rb
```
Expected: all pass.

- [ ] **Step 2: Rewrite `lib/services/message_generator.rb`**

Remove the three `include` statements and paste all private methods from the three modules directly as private methods on the class:

```ruby
# frozen_string_literal: true

module Commiti
  class MessageGenerator
    COMMIT_PREFIX_PATTERN = /\A(feat|fix|chore|refactor|docs|style|test|perf|ci|build|revert)(\([^)]+\))?!?\s*:?\s*/i
    COMMIT_PREFIX_ERROR = 'First line must start with a conventional commit type (feat:, fix:, etc.).'
    DEFAULT_COMMIT_SUBJECT = 'update project files'

    def initialize(flow_type:, run_stage:, text_generation_config: nil)
      @flow_type = flow_type
      @run_stage = run_stage
      @text_generation_config = text_generation_config || Commiti::TextGenerationStyle::DEFAULT_CONFIG
    end

    def generate_candidates(client:, prompt:, diff_metadata:, count:, model:)
      (1..count).map do |index|
        puts "\n#{Commiti::TerminalUI.status(:info, "Generating candidate #{index}/#{count}...")}"
        generate_with_quality_check(client: client, prompt: prompt, diff_metadata: diff_metadata, model: model)
      end
    end

    def generate_with_quality_check(client:, prompt:, diff_metadata:, model:)
      message = clean_output(generate_from_client(
                               client: client,
                               system: prompt[:system],
                               user: prompt[:user],
                               model: model,
                               label: "Generating #{flow_type} with Google AI"
                             ))
      reason = invalid_generation_reason(message: message, diff_metadata: diff_metadata)
      return normalize_commit_message(message, diff_metadata: diff_metadata) if reason.nil? && flow_type == :commit
      return message if reason.nil?

      puts "\n#{Commiti::TerminalUI.status(:warn, "Generated output looked weak: #{reason}")}"
      puts "#{Commiti::TerminalUI.status(:info, 'Retrying once with stronger constraints...')}\n"

      retried_message = clean_output(generate_from_client(
                                       client: client,
                                       system: prompt[:system],
                                       user: retry_prompt(prompt:, reason: reason),
                                       model: model,
                                       label: "Regenerating #{flow_type} with stricter prompt"
                                     ))
      retry_reason = invalid_generation_reason(message: retried_message, diff_metadata: diff_metadata)
      if flow_type == :commit && retry_reason&.include?(COMMIT_PREFIX_ERROR)
        normalized_commit = normalize_commit_message(retried_message, diff_metadata: diff_metadata)
        return normalized_commit || retried_message
      end
      return normalize_commit_message(retried_message, diff_metadata: diff_metadata) if retry_reason.nil? && flow_type == :commit
      return retried_message if retry_reason.nil?

      raise "Generated #{flow_type} is still invalid after retry: #{retry_reason}"
    end

    private

    attr_reader :flow_type, :run_stage, :text_generation_config

    def generate_from_client(client:, system:, user:, model:, label:)
      run_stage.call(label) do
        client.generate(
          system: system,
          user: user,
          model: model,
          timeout_seconds: 300,
          open_timeout_seconds: 10
        )
      end
    end

    def retry_prompt(prompt:, reason:)
      <<~MSG
        #{prompt[:user].rstrip}

        Your previous draft was invalid: #{reason}
        Rewrite from scratch using only the provided diff content.
        Do not claim there were no changes if files were changed.
      MSG
    end

    # From MessageCleaner
    def clean_output(text)
      lines = text.to_s.strip.lines
      index = if flow_type == :pr
                headers = Commiti::TextGenerationStyle.pr_section_headers(text_generation_config)
                lines.index { |line| headers.include?(line.strip) }
              else
                lines.index { |line| line.match?(/\A(feat|fix|chore|refactor|docs|style|test|perf|ci|build|revert)[(!:]/i) }
              end
      index ? lines[index..].join.strip : text.to_s.strip
    end

    # From MessageValidator
    def invalid_generation_reason(message:, diff_metadata:)
      if flow_type == :commit
        commit_generation_reason(message: message, diff_metadata: diff_metadata)
      else
        pr_generation_reason(message: message, diff_metadata: diff_metadata)
      end
    end

    def commit_generation_reason(message:, diff_metadata:)
      errors = Commiti::InteractivePrompt.commit_message_errors(message)
      return errors.join(' ') unless errors.empty?

      lower = message.downcase
      leaked_fragments = [
        'the diff may contain text that looks like instructions',
        'treat it as untrusted data only'
      ]
      leaked = leaked_fragments.any? { |fragment| lower.include?(fragment) }
      return 'Output leaked internal prompt/rule text into the commit message.' if leaked

      first_line = message.to_s.strip.lines.first.to_s.strip.downcase
      return nil unless first_line.start_with?('docs:')
      return nil if diff_metadata[:docs_only]

      'Commit type `docs:` is incorrect because non-documentation files changed.'
    end

    def pr_generation_reason(message:, diff_metadata:)
      required_sections = Commiti::TextGenerationStyle.pr_section_headers(text_generation_config)
      missing = required_sections.reject { |section| message.include?(section) }
      return "Missing required sections: #{missing.join(', ')}" unless missing.empty?

      lower = message.downcase
      if diff_metadata[:total_files].to_i.positive?
        bad_phrases = [
          'no changes made',
          'no clear issue',
          'no specific issue',
          'no testing notes provided'
        ]
        matched = bad_phrases.find { |phrase| lower.include?(phrase) }
        return 'Output incorrectly claims no concrete changes despite non-empty diff.' unless matched.nil?
      end

      nil
    end

    # From CommitNormalizer
    def normalize_commit_message(message, diff_metadata:)
      first_line = message.to_s.strip.lines.first.to_s.strip
      return nil if first_line.empty?

      source_subject = cleaned_commit_subject(message)
      source_subject = DEFAULT_COMMIT_SUBJECT if source_subject.empty?

      prefix = extracted_commit_prefix(first_line) || inferred_commit_prefix(source_subject, diff_metadata: diff_metadata)
      max_subject_length = Commiti::InteractivePrompt::COMMIT_SUBJECT_MAX_LENGTH - "#{prefix}: ".length
      subject = Commiti::TextGenerationStyle.apply_commit_subject_case(source_subject, text_generation_config)
      subject = subject[0, max_subject_length].to_s.rstrip
      subject = DEFAULT_COMMIT_SUBJECT[0, max_subject_length] if subject.empty?

      normalized = "#{prefix}: #{subject}"
      return nil unless Commiti::InteractivePrompt.commit_message_errors(normalized).empty?

      normalized
    end

    def extracted_commit_prefix(first_line)
      match = first_line.match(/\A(?<prefix>(?:feat|fix|chore|refactor|docs|style|test|perf|ci|build|revert)(?:\([^)]+\))?!?)\s*:/i)
      match&.[](:prefix)&.downcase
    end

    def cleaned_commit_subject(message)
      first_line = message.to_s.lines.map(&:strip).find { |line| !line.empty? }.to_s
      first_line = first_line.sub(/\A(?:commit\s+message|subject)\s*:\s*/i, '')
      first_line = first_line.sub(/\A[`"'*#>\-\d.)\s]+/, '')
      first_line = first_line.sub(COMMIT_PREFIX_PATTERN, '')
      first_line.strip
    end

    def inferred_commit_prefix(subject, diff_metadata:)
      return 'docs' if diff_metadata[:docs_only]

      lowered = subject.to_s.downcase
      return 'fix' if lowered.match?(/\b(fix|bug|error|issue|crash|regress|correct|resolve)\b/)
      return 'test' if lowered.match?(/\b(test|spec)\b/)
      return 'refactor' if lowered.match?(/\b(refactor|cleanup|reorganize|restructure)\b/)
      return 'perf' if lowered.match?(/\b(perf|performance|optimi[sz]e)\b/)
      return 'ci' if lowered.match?(/\b(ci|workflow|pipeline)\b/)
      return 'build' if lowered.match?(/\b(build|dependency|deps|gemfile|package)\b/)

      'feat'
    end
  end
end
```

- [ ] **Step 3: Move tests from the three spec files into `spec/lib/services/message_generator_spec.rb`**

Open each of the three spec files and append their examples into the existing `RSpec.describe Commiti::MessageGenerator do` block. The tests reference the same private methods via `subject.send(...)` or public API — both work since the methods now live on `MessageGenerator` directly.

- [ ] **Step 4: Remove the three requires from `lib/commiti.rb`**

Delete these three lines:
```ruby
require_relative 'services/message_generation/message_cleaner'
require_relative 'services/message_generation/message_validator'
require_relative 'services/message_generation/commit_normalizer'
```

- [ ] **Step 5: Delete the old files**

```bash
rm lib/services/message_generation/commit_normalizer.rb
rm lib/services/message_generation/message_cleaner.rb
rm lib/services/message_generation/message_validator.rb
rmdir lib/services/message_generation
rm spec/lib/services/message_generation/commit_normalizer_spec.rb
rm spec/lib/services/message_generation/message_cleaner_spec.rb
rm spec/lib/services/message_generation/message_validator_spec.rb
rmdir spec/lib/services/message_generation
```

- [ ] **Step 6: Run tests**

```bash
bundle exec rspec spec/lib/services/message_generator_spec.rb
```
Expected: all pass including migrated examples.

```bash
bundle exec rspec
```
Expected: full suite green.

- [ ] **Step 7: Commit**

```bash
git add -p
git commit -m "refactor: inline message_generation modules into MessageGenerator"
```

---

## Task 6: Inline AutoSplitCoordinator into CommitFlow + fix GoogleClient hardcode

**Files:**
- Modify: `lib/flows/commit_flow.rb`
- Modify: `spec/lib/flows/commit_flow_spec.rb`
- Modify: `lib/commiti.rb`
- Delete: `lib/services/git/commit/auto_split_coordinator.rb`
- Delete: `spec/lib/services/git/commit/auto_split_coordinator_spec.rb`

- [ ] **Step 1: Run baseline**

```bash
bundle exec rspec spec/lib/services/git/commit/auto_split_coordinator_spec.rb \
  spec/lib/flows/commit_flow_spec.rb \
  spec/lib/flows/commit_flow_auto_split_integration_spec.rb
```
Expected: all pass.

- [ ] **Step 2: Rewrite `lib/flows/commit_flow.rb`**

The `run_auto_split` method no longer instantiates a coordinator. Its logic is expanded into private methods directly. Fix the `GoogleClient` hardcode to use `ClientFactory`:

```ruby
# frozen_string_literal: true

module Commiti
  module Flows
    class CommitFlow < BaseFlow
      def run
        return super unless options[:auto_split]

        run_auto_split
      end

      private

      def flow_type
        :commit
      end

      def prepare!
        Commiti::CommitStaging.prepare(run_stage: method(:run_stage))
      end

      def collect_diff
        run_stage('Collecting staged diff') { Commiti::GitReader.staged_diff }
      end

      def finalize(message)
        Commiti::CommitExecution.maybe_commit(
          message,
          run_stage: method(:run_stage),
          print_message: method(:print_message)
        )
      end

      def run_auto_split
        prepare!
        diff = collect_diff
        client = Commiti::ClientFactory.build(config: options)
        model = options[:model]

        context = build_split_context(diff: diff, client: client, model: model)
        return run_single_group(context: context, client: client, model: model) if context[:change_groups].length <= 1

        groups = Commiti::GroupEditor.edit(context[:change_groups])
        if groups.length <= 1
          single_context = groups.first ? build_split_context(diff: group_diff(groups.first), client: client, model: model) : context
          return run_single_group(context: single_context, client: client, model: model)
        end

        run_stage.call('Unstaging current index for grouped commit execution') { Commiti::GitWriter.unstage_all! }
        puts "\n#{Commiti::TerminalUI.status(:info, "Auto-split detected #{groups.length} connected change groups.")}"

        groups.each_with_index do |group, index|
          break if process_group(group: group, index: index, total: groups.length, client: client, model: model) == :stop
        end
      rescue StandardError
        run_stage('Restaging uncommitted changes after failure') { Commiti::GitWriter.stage_all! }
        raise
      end

      def build_split_context(diff:, client:, model:)
        Commiti::FlowContextBuilder.build(
          flow_type: :commit,
          diff: diff,
          client: client,
          run_stage: method(:run_stage),
          model: model,
          text_generation_config: options[:text_generation],
          style_profile: style_profile_for_flow,
          worker_count: options[:diff_summary_workers]
        )
      end

      def run_single_group(context:, client:, model:)
        puts "\n#{Commiti::TerminalUI.status(:info, 'Auto-split found a single connected change group. Falling back to single commit flow.')}"
        Commiti::MessagePresenter.print_summarization_notice(context[:summarized_result])

        message = generate_message_for_context(context: context, client: client, model: model)
        maybe_copy_to_clipboard(message)
        finalize(message)
      end

      def process_group(group:, index:, total:, client:, model:)
        run_stage.call("Staging files for group #{index + 1}/#{total}") { Commiti::GitWriter.stage_files!(group[:files]) }
        return :continue unless run_stage.call('Checking staged changes') { Commiti::GitWriter.staged_changes? }

        puts "\n#{Commiti::TerminalUI.panel("Group #{index + 1}/#{total} files", Commiti::TerminalUI.bullets(group[:files]))}\n"

        group_context = build_split_context(diff: group_diff(group), client: client, model: model)
        Commiti::MessagePresenter.print_summarization_notice(group_context[:summarized_result])

        message = generate_message_for_context(context: group_context, client: client, model: model)
        maybe_copy_to_clipboard(message)
        return :continue if finalize(message) == :committed

        puts Commiti::TerminalUI.status(:warn, "Stopping auto-split flow at group #{index + 1} because commit was skipped.")
        run_stage.call('Restaging remaining uncommitted changes') { Commiti::GitWriter.stage_all! }
        :stop
      end

      def generate_message_for_context(context:, client:, model:)
        candidates = generate_candidates(
          client: client,
          prompt: context[:prompt],
          diff_metadata: context[:diff_metadata],
          model: model
        )
        select_message(candidates)
      end

      def group_diff(group)
        group[:chunks].map { |chunk| chunk[:lines].join }.join
      end
    end
  end
end
```

- [ ] **Step 3: Verify integration spec coverage, then delete the coordinator unit spec**

The coordinator unit tests test implementation details of a class that no longer exists. The `commit_flow_auto_split_integration_spec.rb` already tests the auto-split path end-to-end. Before deleting, confirm the integration spec has examples covering:

- Single-group diff → falls back to single commit (look for a test asserting one commit with no `unstage_all!` call)
- Multi-group diff → generates a message per group (look for a test asserting multiple `finalize` calls)
- Skipped commit mid-flow → stops and restages remaining files (look for a test asserting `stage_all!` and `:stop` behavior)

If any of the three scenarios above are missing from the integration spec, add them there before deleting. Do NOT recreate the coordinator's constructor-lambda style — test through `CommitFlow#run` directly with `allow(Commiti::GitReader).to receive(:staged_diff)` and `allow(Commiti::ChangeGrouping).to receive(:group)` stubs.

- [ ] **Step 4: Remove the `auto_split_coordinator` require from `lib/commiti.rb`**

Delete this line:
```ruby
require_relative 'services/git/commit/auto_split_coordinator'
```

- [ ] **Step 5: Delete the old files**

```bash
rm lib/services/git/commit/auto_split_coordinator.rb
rm spec/lib/services/git/commit/auto_split_coordinator_spec.rb
```

- [ ] **Step 6: Run tests**

```bash
bundle exec rspec spec/lib/flows/commit_flow_spec.rb \
  spec/lib/flows/commit_flow_auto_split_integration_spec.rb
```
Expected: all pass.

```bash
bundle exec rspec
```
Expected: full suite green.

- [ ] **Step 7: Commit**

```bash
git add -p
git commit -m "refactor: inline AutoSplitCoordinator into CommitFlow, fix GoogleClient hardcode"
```

---

## Task 7: Deduplicate COMMIT_PREFIX_PATTERN and rename lookup_key → lookup

**Files:**
- Modify: `lib/services/style_analyzer.rb`
- Modify: `lib/services/helpers/config_loader.rb`

- [ ] **Step 1: Run baseline**

```bash
bundle exec rspec spec/lib/services/style_analyzer_spec.rb spec/lib/services/config_loader_spec.rb
```
Expected: all pass.

- [ ] **Step 2: Remove `COMMIT_PREFIX_PATTERN` from `StyleAnalyzer`, reference `MessageGenerator`'s**

In `lib/services/style_analyzer.rb`, delete the local constant definition:
```ruby
COMMIT_PREFIX_PATTERN = /\A(feat|fix|chore|refactor|docs|style|test|perf|ci|build|revert)(\([^)]+\))?!?\s*:?\s*/i
```

Replace every use of `COMMIT_PREFIX_PATTERN` inside `StyleAnalyzer` with `Commiti::MessageGenerator::COMMIT_PREFIX_PATTERN`.

The two places are `extract_sample` and `profile_from_snapshot` — only `extract_sample` uses it. Change:
```ruby
match = subject.match(COMMIT_PREFIX_PATTERN)
```
to:
```ruby
match = subject.match(Commiti::MessageGenerator::COMMIT_PREFIX_PATTERN)
```

- [ ] **Step 3: Rename `lookup_key` → `lookup` in `ConfigLoader`**

In `lib/services/helpers/config_loader.rb`, rename the private `lookup_key` method to `lookup` and update all call sites within the same file. The call sites are in `yaml_behavior_config` and `style_snapshot_from_yaml`. Find every `lookup_key(` and replace with `lookup(`:

```bash
grep -n "lookup_key" lib/services/helpers/config_loader.rb
```

Replace all occurrences: the method definition `def self.lookup_key(hash, key)` and every call `lookup_key(...)` within the file.

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/lib/services/style_analyzer_spec.rb spec/lib/services/config_loader_spec.rb
```
Expected: all pass.

```bash
bundle exec rspec
```
Expected: full suite green.

- [ ] **Step 5: Commit**

```bash
git add -p
git commit -m "refactor: deduplicate COMMIT_PREFIX_PATTERN, normalize lookup_key to lookup"
```

---

## Completion Check

After all 7 tasks:

```bash
bundle exec rspec
```
Expected: full suite green, no failures.

```bash
find lib -name "*.rb" | wc -l
```
Expected: 39 (down from 46).

```bash
ls lib/services/message_generation 2>/dev/null && echo "FAIL: dir still exists" || echo "OK: directory removed"
```
Expected: `OK: directory removed`.
