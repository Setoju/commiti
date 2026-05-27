# Unified Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all non-secret behavior flags out of env vars and into `.commiti.yml` / `~/.commiti.yml`, with a global-to-project-to-env-var precedence chain.

**Architecture:** `ConfigLoader.load` loads `~/.commiti.yml` (global) and `.commiti.yml` (project), deep-merges them, extracts behavior flags as base values, then applies env var overrides on top. `DiffSummarizer` receives `worker_count` from config instead of reading `ENV` directly.

**Tech Stack:** Ruby, YAML (safe_load, already in use), RSpec

---

## File Map

| File | Change |
|---|---|
| `lib/services/helpers/config_loader.rb` | Add global loading, deep merge, YAML flag extraction, env-only overrides |
| `lib/services/diff_summarization/batch_runner.rb` | Accept `worker_count:` kwarg in `summarize_chunks`, `run_async_summary_jobs`, `summary_worker_count` |
| `lib/services/diff_summarization/diff_summarizer.rb` | Accept and thread `worker_count:` in `summarize_if_needed` |
| `lib/services/flow_context_builder.rb` | Accept and thread `worker_count:` in `build` |
| `lib/flows/base_flow.rb` | Pass `worker_count: options[:diff_summary_workers]` to `FlowContextBuilder.build` |
| `lib/flows/commit_flow.rb` | Pass `worker_count: options[:diff_summary_workers]` to `FlowContextBuilder.build` |
| `spec/lib/services/config_loader_spec.rb` | New tests for YAML precedence layers |
| `README.md` | Document new YAML keys |

---

## Task 1: Add `deep_merge`, `global_config_path`, and `load_global_yaml` to ConfigLoader

**Files:**
- Modify: `lib/services/helpers/config_loader.rb`
- Test: `spec/lib/services/config_loader_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/lib/services/config_loader_spec.rb` inside `RSpec.describe Commiti::ConfigLoader do`, after the existing `describe '.load'` block:

```ruby
describe '.deep_merge (private)' do
  it 'overrides scalar values from the override hash' do
    base = { model: 'gemma', candidates: 1 }
    override = { model: 'gemini-flash' }

    result = described_class.send(:deep_merge, base, override)

    expect(result[:model]).to eq('gemini-flash')
    expect(result[:candidates]).to eq(1)
  end

  it 'recursively merges nested hashes' do
    base = { text_generation: { commit: { subject_case: 'preserve' }, pr: { sections: [] } } }
    override = { text_generation: { commit: { subject_case: 'uppercase' } } }

    result = described_class.send(:deep_merge, base, override)

    expect(result[:text_generation][:commit][:subject_case]).to eq('uppercase')
    expect(result[:text_generation][:pr]).to eq({ sections: [] })
  end

  it 'replaces arrays entirely rather than appending' do
    base = { 'pr' => { 'sections' => %w[A B] } }
    override = { 'pr' => { 'sections' => ['C'] } }

    result = described_class.send(:deep_merge, base, override)

    expect(result['pr']['sections']).to eq(['C'])
  end
end

describe '.global_config_path (private)' do
  it 'returns the expanded path to ~/.commiti.yml' do
    expected = File.expand_path('~/.commiti.yml')

    expect(described_class.send(:global_config_path)).to eq(expected)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/services/config_loader_spec.rb --format documentation 2>&1 | tail -20
```

Expected: failures with `NoMethodError: undefined method 'deep_merge'`

- [ ] **Step 3: Add `deep_merge`, `global_config_path`, and `load_global_yaml` to ConfigLoader**

Add the following private class methods inside `class ConfigLoader`, after the existing `read_yaml_config` method (after line 68):

```ruby
def self.global_config_path
  File.expand_path('~/.commiti.yml')
end
private_class_method :global_config_path

def self.load_global_yaml
  read_yaml_config(global_config_path)
end
private_class_method :load_global_yaml

def self.deep_merge(base, override)
  base.merge(override) do |_key, old_val, new_val|
    if old_val.is_a?(Hash) && new_val.is_a?(Hash)
      deep_merge(old_val, new_val)
    else
      new_val
    end
  end
end
private_class_method :deep_merge
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rspec spec/lib/services/config_loader_spec.rb --format documentation 2>&1 | tail -20
```

Expected: all new tests PASS, existing tests unaffected

- [ ] **Step 5: Commit**

```bash
git add lib/services/helpers/config_loader.rb spec/lib/services/config_loader_spec.rb
git commit -m "feat: add deep_merge and global config path helpers to ConfigLoader"
```

---

## Task 2: Read behavior flags from merged YAML in ConfigLoader

**Files:**
- Modify: `lib/services/helpers/config_loader.rb`
- Test: `spec/lib/services/config_loader_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add a new `describe '.load with YAML config'` block to `spec/lib/services/config_loader_spec.rb` after the existing `describe '.load'` block:

```ruby
describe '.load with YAML behavior config' do
  let(:env) { {} }

  it 'reads model and candidates from a project config file' do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, '.commiti.yml')
      File.write(config_path, <<~YAML)
        model: gemini-2.5-flash
        candidates: 3
        no_copy: true
        auto_split: true
        diff_summary_workers: 6
        git:
          base_branch: develop
      YAML

      config = described_class.load(env: { 'COMMITI_CONFIG' => config_path }, cwd: dir)

      expect(config[:model]).to eq('gemini-2.5-flash')
      expect(config[:candidates]).to eq(3)
      expect(config[:no_copy]).to be(true)
      expect(config[:auto_split]).to be(true)
      expect(config[:diff_summary_workers]).to eq(6)
      expect(config[:base_branch]).to eq('develop')
    end
  end

  it 'env vars override YAML behavior flags' do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, '.commiti.yml')
      File.write(config_path, "model: gemini-2.5-flash\ncandidates: 3\n")

      config = described_class.load(
        env: { 'COMMITI_CONFIG' => config_path, 'COMMITI_MODEL' => 'gemma-4-31b-it', 'COMMITI_CANDIDATES' => '1' },
        cwd: dir
      )

      expect(config[:model]).to eq('gemma-4-31b-it')
      expect(config[:candidates]).to eq(1)
    end
  end

  it 'absent env vars do not overwrite YAML values' do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, '.commiti.yml')
      File.write(config_path, "model: gemini-2.5-flash\n")

      config = described_class.load(env: { 'COMMITI_CONFIG' => config_path }, cwd: dir)

      expect(config[:model]).to eq('gemini-2.5-flash')
    end
  end

  it 'global config provides defaults that project config overrides' do
    Dir.mktmpdir do |global_dir|
      Dir.mktmpdir do |project_dir|
        global_path = File.join(global_dir, '.commiti.yml')
        project_path = File.join(project_dir, '.commiti.yml')

        File.write(global_path, "model: gemini-2.5-flash\ncandidates: 2\n")
        File.write(project_path, "candidates: 5\n")

        allow(described_class).to receive(:global_config_path).and_return(global_path)

        config = described_class.load(env: { 'COMMITI_CONFIG' => project_path }, cwd: project_dir)

        expect(config[:model]).to eq('gemini-2.5-flash')
        expect(config[:candidates]).to eq(5)
      end
    end
  end

  it 'project text_generation overrides global without wiping other global text_generation keys' do
    Dir.mktmpdir do |global_dir|
      Dir.mktmpdir do |project_dir|
        global_path = File.join(global_dir, '.commiti.yml')
        project_path = File.join(project_dir, '.commiti.yml')

        File.write(global_path, <<~YAML)
          text_generation:
            commit:
              subject_case: lowercase
            pr:
              sections:
                - name: Global Section
                  guidance: Global guidance.
        YAML
        File.write(project_path, <<~YAML)
          text_generation:
            commit:
              subject_case: uppercase
        YAML

        allow(described_class).to receive(:global_config_path).and_return(global_path)

        config = described_class.load(env: { 'COMMITI_CONFIG' => project_path }, cwd: project_dir)

        expect(config[:text_generation][:commit][:subject_case]).to eq('uppercase')
        expect(config[:text_generation][:pr][:sections].first[:name]).to eq('Global Section')
      end
    end
  end

  it 'does not read API key secrets from YAML' do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, '.commiti.yml')
      File.write(config_path, "google_api_key: should-be-ignored\n")

      config = described_class.load(env: { 'COMMITI_CONFIG' => config_path }, cwd: dir)

      expect(config[:google_api_key]).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/services/config_loader_spec.rb --format documentation 2>&1 | tail -30
```

Expected: new tests fail with unexpected values (YAML flags not yet read)

- [ ] **Step 3: Add `yaml_behavior_config`, `as_boolean`, `safe_integer`, and `env_behavior_overrides` private methods**

Add after `load_global_yaml` in `config_loader.rb`:

```ruby
def self.yaml_behavior_config(merged)
  git = lookup_key(merged, 'git') || {}
  {}.tap do |result|
    model = present_or_nil(lookup_key(merged, 'model').to_s)
    result[:model] = model if model

    candidates = safe_integer(lookup_key(merged, 'candidates'))
    result[:candidates] = candidates unless candidates.nil?

    base_branch = present_or_nil(lookup_key(git, 'base_branch').to_s)
    result[:base_branch] = base_branch if base_branch

    no_copy = as_boolean(lookup_key(merged, 'no_copy'))
    result[:no_copy] = no_copy unless no_copy.nil?

    auto_split = as_boolean(lookup_key(merged, 'auto_split'))
    result[:auto_split] = auto_split unless auto_split.nil?

    workers = safe_integer(lookup_key(merged, 'diff_summary_workers'))
    result[:diff_summary_workers] = workers unless workers.nil?
  end
end
private_class_method :yaml_behavior_config

def self.env_behavior_overrides(env)
  {}.tap do |result|
    model = present_or_nil(env.fetch('COMMITI_MODEL', nil))
    result[:model] = model if model

    candidates = safe_integer(env.fetch('COMMITI_CANDIDATES', nil))
    result[:candidates] = candidates unless candidates.nil?

    base_branch = present_or_nil(env.fetch('COMMITI_BASE_BRANCH', nil))
    result[:base_branch] = base_branch if base_branch

    no_copy = safe_boolean_from_string(env.fetch('COMMITI_NO_COPY', nil))
    result[:no_copy] = no_copy unless no_copy.nil?

    auto_split = safe_boolean_from_string(env.fetch('COMMITI_AUTO_SPLIT', nil))
    result[:auto_split] = auto_split unless auto_split.nil?

    temperature = safe_float(env.fetch('COMMITI_MODEL_TEMPERATURE', nil))
    result[:temperature] = temperature unless temperature.nil?

    timeout = safe_integer(env.fetch('COMMITI_MODEL_TIMEOUT_SECONDS', nil))
    result[:timeout_seconds] = timeout unless timeout.nil?

    open_timeout = safe_integer(env.fetch('COMMITI_MODEL_OPEN_TIMEOUT_SECONDS', nil))
    result[:open_timeout_seconds] = open_timeout unless open_timeout.nil?
  end
end
private_class_method :env_behavior_overrides

def self.lookup_key(hash, key)
  return nil unless hash.is_a?(Hash)
  hash[key] || hash[key.to_sym]
end
private_class_method :lookup_key

def self.as_boolean(value)
  return value if value == true || value == false
  nil
end
private_class_method :as_boolean

def self.safe_integer(value)
  return nil if value.nil? || value.to_s.strip.empty?
  Integer(value)
rescue ArgumentError, TypeError
  nil
end
private_class_method :safe_integer

def self.safe_float(value)
  return nil if value.nil? || value.to_s.strip.empty?
  Float(value)
rescue ArgumentError, TypeError
  nil
end
private_class_method :safe_float

def self.safe_boolean_from_string(value)
  return nil if value.nil? || value.to_s.strip.empty?
  normalized = value.to_s.strip.downcase
  return true if %w[1 true yes on].include?(normalized)
  return false if %w[0 false no off].include?(normalized)
  nil
end
private_class_method :safe_boolean_from_string
```

- [ ] **Step 4: Update `load` to use merged YAML + env overrides**

Replace the entire `self.load` method in `config_loader.rb`:

```ruby
def self.load(env: ENV, cwd: Dir.pwd)
  global_raw = load_global_yaml
  project_raw = read_yaml_config(configured_path(env: env, cwd: cwd))
  merged_raw = deep_merge(global_raw, project_raw)

  DEFAULT_CONFIG
    .merge(yaml_behavior_config(merged_raw))
    .merge(
      google_api_key: google_api_key_from_env(env),
      github_token: present_or_nil(env.fetch('COMMITI_GITHUB_TOKEN', nil)),
      gitlab_token: present_or_nil(env.fetch('COMMITI_GITLAB_TOKEN', nil)),
      gitbucket_token: present_or_nil(env.fetch('COMMITI_GITBUCKET_TOKEN', nil)),
      text_generation: Commiti::TextGenerationStyle.normalize(merged_raw)
    )
    .merge(env_behavior_overrides(env))
end
```

Also delete the now-unused `load_text_generation_config` and `configured_path` private methods and replace `configured_path` inline — wait, `configured_path` is still needed. Keep it. Remove only `load_text_generation_config`:

Delete these lines from `config_loader.rb`:
```ruby
def self.load_text_generation_config(env:, cwd:)
  config_path = configured_path(env: env, cwd: cwd)
  project_config = read_yaml_config(config_path)
  Commiti::TextGenerationStyle.normalize(project_config)
end
private_class_method :load_text_generation_config
```

Also remove the existing `integer_or_default`, `float_or_default`, and `boolean_or_default` private methods — they are now replaced by `safe_integer`, `safe_float`, and `safe_boolean_from_string`. (Check no other files use them first: `grep -rn "integer_or_default\|float_or_default\|boolean_or_default" lib/`)

- [ ] **Step 5: Delete the now-unused private methods from ConfigLoader**

Remove these three method bodies from `lib/services/helpers/config_loader.rb` (they are replaced by `safe_integer`, `safe_float`, `safe_boolean_from_string`):

```ruby
def self.load_text_generation_config(env:, cwd:)
  config_path = configured_path(env: env, cwd: cwd)
  project_config = read_yaml_config(config_path)
  Commiti::TextGenerationStyle.normalize(project_config)
end
private_class_method :load_text_generation_config
```

```ruby
def self.integer_or_default(value, fallback)
  return fallback if value.nil? || value.to_s.strip.empty?

  Integer(value)
rescue ArgumentError
  fallback
end
private_class_method :integer_or_default
```

```ruby
def self.float_or_default(value, fallback)
  return fallback if value.nil? || value.to_s.strip.empty?

  Float(value)
rescue ArgumentError
  fallback
end
private_class_method :float_or_default
```

```ruby
def self.boolean_or_default(value, fallback)
  return fallback if value.nil? || value.to_s.strip.empty?

  normalized = value.to_s.strip.downcase
  return true if %w[1 true yes on].include?(normalized)
  return false if %w[0 false no off].include?(normalized)

  fallback
end
private_class_method :boolean_or_default
```

Verify they are gone and nothing else references them:
```bash
grep -rn "integer_or_default\|float_or_default\|boolean_or_default\|load_text_generation_config" lib/
```

Expected: no output

- [ ] **Step 6: Run the full config_loader spec**

```bash
bundle exec rspec spec/lib/services/config_loader_spec.rb --format documentation
```

Expected: all tests PASS including old and new tests

- [ ] **Step 7: Run the full test suite**

```bash
bundle exec rspec --format progress 2>&1 | tail -10
```

Expected: no new failures

- [ ] **Step 8: Commit**

```bash
git add lib/services/helpers/config_loader.rb spec/lib/services/config_loader_spec.rb
git commit -m "feat: read behavior flags from YAML config with global/project/env precedence"
```

---

## Task 3: Thread `diff_summary_workers` through the summarizer stack

**Files:**
- Modify: `lib/services/diff_summarization/batch_runner.rb`
- Modify: `lib/services/diff_summarization/diff_summarizer.rb`
- Modify: `lib/services/flow_context_builder.rb`
- Modify: `lib/flows/base_flow.rb`
- Modify: `lib/flows/commit_flow.rb`
- Test: `spec/lib/services/diff_summarizer_spec.rb`

- [ ] **Step 1: Write a failing test for `summarize_if_needed` with `worker_count`**

Open `spec/lib/services/diff_summarizer_spec.rb`. Find the existing test that exercises `summarize_if_needed` with a large diff (look for a test that stubs `client.generate`). Add this test in the same describe block:

```ruby
it 'passes worker_count through to summarize_chunks' do
  large_diff = "diff --git a/foo.rb b/foo.rb\n" + ("+" * 9000)
  allow(Commiti::DiffParser).to receive(:split_by_file).and_return(
    [{ path: 'foo.rb', diff: large_diff }]
  )
  expect(Commiti::DiffSummarizer).to receive(:summarize_chunks).with(
    anything,
    hash_including(worker_count: 2)
  ).and_call_original

  allow(client).to receive(:generate).and_return('summary')

  Commiti::DiffSummarizer.summarize_if_needed(large_diff, client: client, model: 'gemma', worker_count: 2)
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
bundle exec rspec spec/lib/services/diff_summarizer_spec.rb --format documentation 2>&1 | tail -15
```

Expected: FAIL — `summarize_if_needed` does not accept `worker_count:`

- [ ] **Step 3: Update `batch_runner.rb` to accept `worker_count:` kwargs**

In `lib/services/diff_summarization/batch_runner.rb`, make these three changes:

Change `summarize_chunks` signature from:
```ruby
def summarize_chunks(chunks, client:, model:)
```
to:
```ruby
def summarize_chunks(chunks, client:, model:, worker_count: nil)
```

Change the `run_async_summary_jobs` call inside `summarize_chunks` from:
```ruby
run_async_summary_jobs(batched_jobs, results: results, client: client, model: model) unless batched_jobs.empty?
```
to:
```ruby
run_async_summary_jobs(batched_jobs, results: results, client: client, model: model, worker_count: worker_count) unless batched_jobs.empty?
```

Change `run_async_summary_jobs` signature from:
```ruby
def run_async_summary_jobs(jobs, results:, client:, model:)
```
to:
```ruby
def run_async_summary_jobs(jobs, results:, client:, model:, worker_count: nil)
```

Change the `worker_count = summary_worker_count(jobs.length)` line inside `run_async_summary_jobs` from:
```ruby
worker_count = summary_worker_count(jobs.length)
```
to:
```ruby
worker_count = summary_worker_count(jobs.length, configured_count: worker_count)
```

Change `summary_worker_count` from:
```ruby
def summary_worker_count(job_count)
  configured = Integer(ENV.fetch('DIFF_SUMMARY_WORKERS', DEFAULT_SUMMARY_WORKERS))
  configured.clamp(1, job_count)
rescue ArgumentError
  DEFAULT_SUMMARY_WORKERS.clamp(1, job_count)
end
```
to:
```ruby
def summary_worker_count(job_count, configured_count: nil)
  count = configured_count || Integer(ENV.fetch('DIFF_SUMMARY_WORKERS', DEFAULT_SUMMARY_WORKERS))
  count.clamp(1, job_count)
rescue ArgumentError
  DEFAULT_SUMMARY_WORKERS.clamp(1, job_count)
end
```

- [ ] **Step 4: Update `diff_summarizer.rb` to accept and thread `worker_count:`**

Change `summarize_if_needed` signature from:
```ruby
def self.summarize_if_needed(diff, client:, model: Commiti::GoogleClient::DEFAULT_MODEL, chunks: nil)
```
to:
```ruby
def self.summarize_if_needed(diff, client:, model: Commiti::GoogleClient::DEFAULT_MODEL, chunks: nil, worker_count: nil)
```

Change the `summarize_chunks` call inside `summarize_if_needed` from:
```ruby
per_file_summaries = summarize_chunks(parsed_chunks, client: client, model: model)
```
to:
```ruby
per_file_summaries = summarize_chunks(parsed_chunks, client: client, model: model, worker_count: worker_count)
```

- [ ] **Step 5: Update `flow_context_builder.rb` to accept and thread `worker_count:`**

Change `build` signature from:
```ruby
def self.build(flow_type:, diff:, client:, run_stage:, model:, text_generation_config: nil)
```
to:
```ruby
def self.build(flow_type:, diff:, client:, run_stage:, model:, text_generation_config: nil, worker_count: nil)
```

Change the `summarize_if_needed` call inside `build` from:
```ruby
Commiti::DiffSummarizer.summarize_if_needed(
  diff,
  client: client,
  model: model,
  chunks: summary_chunks(line_chunks)
)
```
to:
```ruby
Commiti::DiffSummarizer.summarize_if_needed(
  diff,
  client: client,
  model: model,
  chunks: summary_chunks(line_chunks),
  worker_count: worker_count
)
```

- [ ] **Step 6: Update `base_flow.rb` to pass `worker_count`**

In `lib/flows/base_flow.rb`, change the `FlowContextBuilder.build` call from:
```ruby
context = Commiti::FlowContextBuilder.build(
  flow_type: flow_type,
  diff: diff,
  client: client,
  run_stage: method(:run_stage),
  model: selected_model,
  text_generation_config: options[:text_generation]
)
```
to:
```ruby
context = Commiti::FlowContextBuilder.build(
  flow_type: flow_type,
  diff: diff,
  client: client,
  run_stage: method(:run_stage),
  model: selected_model,
  text_generation_config: options[:text_generation],
  worker_count: options[:diff_summary_workers]
)
```

- [ ] **Step 7: Update `commit_flow.rb` to pass `worker_count`**

In `lib/flows/commit_flow.rb`, find the `build_context` private method (around line 98) and change:
```ruby
def build_context(diff:, client:, model:)
  Commiti::FlowContextBuilder.build(
    flow_type: flow_type,
    diff: diff,
    client: client,
    run_stage: method(:run_stage),
    model: model
  )
end
```
to:
```ruby
def build_context(diff:, client:, model:)
  Commiti::FlowContextBuilder.build(
    flow_type: flow_type,
    diff: diff,
    client: client,
    run_stage: method(:run_stage),
    model: model,
    worker_count: options[:diff_summary_workers]
  )
end
```

- [ ] **Step 8: Run the diff_summarizer spec**

```bash
bundle exec rspec spec/lib/services/diff_summarizer_spec.rb --format documentation 2>&1 | tail -20
```

Expected: all tests PASS including the new `worker_count` test

- [ ] **Step 9: Run the full test suite**

```bash
bundle exec rspec --format progress 2>&1 | tail -10
```

Expected: no failures

- [ ] **Step 10: Commit**

```bash
git add lib/services/diff_summarization/batch_runner.rb \
        lib/services/diff_summarization/diff_summarizer.rb \
        lib/services/flow_context_builder.rb \
        lib/flows/base_flow.rb \
        lib/flows/commit_flow.rb \
        spec/lib/services/diff_summarizer_spec.rb
git commit -m "feat: thread diff_summary_workers from config through summarizer stack"
```

---

## Task 4: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Configuration section**

In `README.md`, find the `## Configuration` section. Replace the existing env var block comment for `COMMITI_MODEL`, `COMMITI_CANDIDATES`, `COMMITI_BASE_BRANCH`, `COMMITI_NO_COPY`, `COMMITI_AUTO_SPLIT` with a note that these are now settable in `.commiti.yml`.

Find this block in the `.env` example:
```dotenv
# Optional overrides:
# COMMITI_MODEL=gemma-4-31b-it
# COMMITI_CANDIDATES=1
# COMMITI_BASE_BRANCH=main
# COMMITI_NO_COPY=false
# COMMITI_AUTO_SPLIT=false
```

Replace it with:
```dotenv
# Optional overrides (prefer .commiti.yml for these — env vars take precedence when set):
# COMMITI_MODEL=gemma-4-31b-it
# COMMITI_CANDIDATES=1
# COMMITI_BASE_BRANCH=main
# COMMITI_NO_COPY=false
# COMMITI_AUTO_SPLIT=false
```

- [ ] **Step 2: Document the global config file**

Find the paragraph starting with `For project-specific wording and structure, add a `.commiti.yml` file at the repo root:` and add a paragraph before it:

```
A global `~/.commiti.yml` sets personal defaults across all repositories. A project `.commiti.yml` overrides the global file for that repo. Env vars override both.
```

- [ ] **Step 3: Expand the `.commiti.yml` example**

Find the existing `.commiti.yml` YAML block:
```yaml
text_generation:
  commit:
    subject_case: uppercase # uppercase, lowercase, or preserve
  pr:
    sections:
      - name: Overview
        guidance: Summarize the change in one paragraph.
      - name: Validation
        guidance: Describe the checks or tests that were run.
```

Replace it with:
```yaml
# Behavior settings (also settable in ~/.commiti.yml for global defaults)
model: gemma-4-31b-it          # AI model to use
candidates: 1                  # number of message candidates to generate (1–5)
auto_split: false              # auto-group staged changes into multiple commits
no_copy: false                 # skip copying output to clipboard
diff_summary_workers: 4        # parallel workers for large-diff summarization

git:
  base_branch: main            # base branch for PR diffs

text_generation:
  commit:
    subject_case: uppercase    # uppercase, lowercase, or preserve
  pr:
    sections:
      - name: Overview
        guidance: Summarize the change in one paragraph.
      - name: Validation
        guidance: Describe the checks or tests that were run.
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document unified YAML config with global and project file support"
```
