# Full App Refactor — Design Spec

**Date:** 2026-05-29
**Branch:** refactor/full-app-ref
**Scope:** Code quality + architecture. No provider abstraction, no public API changes.

---

## Goals

- Fix the `text_generation_config` forwarding bug in `CommitFlow#build_context`
- Eliminate code duplication between `BaseFlow` and `ChangelogFlow`
- Extract auto-split orchestration from `CommitFlow` into its own class
- Split `MessageGeneratorSupport` into focused single-responsibility modules
- Fix `GoogleClient` method visibility (only `generate` is public)
- Remove implicit module composition in `DiffSummarizer`
- Simplify `ConfigLoader` pattern (replace `.tap` with `.compact`)
- Delete dead and duplicate spec files

---

## 1. Flow Hierarchy

### New: `FlowBase`

A thin shared base extracted from `BaseFlow` and `ChangelogFlow`.

**File:** `lib/flows/flow_base.rb`

**Responsibilities:**
- `initialize(options:)` — loads config via `ConfigLoader.load`, merges CLI options (CLI wins)
- `run_stage(label, &block)` — wraps `Spinner.run`
- `attr_reader :options`

**Does not own:** AI client, diff collection, message generation, or any flow-specific logic.

### `BaseFlow < FlowBase`

Unchanged interface. Inherits config loading and `run_stage` from `FlowBase`. Continues to own the AI generation pipeline: collect diff → build context → generate candidates → select → copy → finalize.

### `CommitFlow < BaseFlow`

`run` delegates to `AutoSplitCoordinator` when `options[:auto_split]` is true.  
`build_context` is fixed to forward `text_generation_config` (existing bug).  
`run_auto_split` is removed — replaced by `AutoSplitCoordinator`.

### `PrFlow < BaseFlow`

No changes.

### `ChangelogFlow < FlowBase`

Was standalone. Now inherits `FlowBase` for config loading and `run_stage`. Removes duplicate `initialize` and `run_stage`.

---

## 2. AutoSplitCoordinator

**File:** `lib/services/git/commit/auto_split_coordinator.rb`

Owns all multi-group orchestration currently in `CommitFlow`.

**Interface:**
```ruby
AutoSplitCoordinator.new(
  options:,
  client:,
  model:,
  run_stage:,
  generate_candidates:,  # callable
  select_message:,       # callable
  finalize:,             # callable
  maybe_copy_to_clipboard: # callable
).run
```

**Internal methods:**
- `run` — prepares diff, builds context, dispatches to single or grouped path
- `run_single_group_context(context:)` — falls back to single commit flow with a notice
- `run_grouped_context(context:)` — invokes `GroupEditor`, iterates groups
- `process_group(group:, index:, total:)` — stages, generates, finalizes one group
- `build_context(diff:)` — wraps `FlowContextBuilder.build` with coordinator's settings
- `group_diff(group)` — reconstructs raw diff text from a group's chunks

Error recovery (`Restaging uncommitted changes after failure`) stays in `CommitFlow#run_auto_split`, which wraps the coordinator call in `rescue`.

**Spec:** `spec/lib/services/git/commit/auto_split_coordinator_spec.rb`

---

## 3. Message Generation Modules

`MessageGeneratorSupport` is deleted. Its responsibilities move to three focused modules under a new directory.

**Directory:** `lib/services/message_generation/`

### `MessageCleaner`

**File:** `lib/services/message_generation/message_cleaner.rb`

Single method: `clean_output(text)` — strips preamble before the real content (first conventional commit prefix for commit flow, first PR section header for PR flow).

### `MessageValidator`

**File:** `lib/services/message_generation/message_validator.rb`

Methods:
- `invalid_generation_reason(message:, diff_metadata:)` — dispatches to commit or PR validator
- `commit_generation_reason(message:, diff_metadata:)` — checks conventional commit prefix, leaked prompt text, incorrect `docs:` usage
- `pr_generation_reason(message:, diff_metadata:)` — checks required sections, bad phrases

### `CommitNormalizer`

**File:** `lib/services/message_generation/commit_normalizer.rb`

Methods:
- `normalize_commit_message(message, diff_metadata:)` — assembles `prefix: subject`
- `extracted_commit_prefix(first_line)` — extracts existing prefix if valid
- `cleaned_commit_subject(message)` — strips decoration from first line
- `inferred_commit_prefix(subject, diff_metadata:)` — infers type from subject keywords

### `MessageGenerator`

Includes all three modules. `message_generator_support.rb` is deleted.

**Spec files:**
- `spec/lib/services/message_generation/message_cleaner_spec.rb`
- `spec/lib/services/message_generation/message_validator_spec.rb`
- `spec/lib/services/message_generation/commit_normalizer_spec.rb`
- `spec/lib/services/message_generator_support_spec.rb` is deleted

---

## 4. Service Structural Fixes

### `GoogleClient` — visibility

Only `generate` is public. All implementation methods become private:
`normalize_model`, `normalize_api_key`, `normalize_numeric`, `extract_error`, `extract_content`, `request_settings`, `extract_generated_content`, `generate_content`, `request_body`.

Specs that reach into private methods are rewritten to test through `generate` (using stubs at the HTTP layer).

### `DiffSummarizer` — composition

`extend BatchRunner` and `extend FallbackBuilder` are removed.

`BatchRunner` and `FallbackBuilder` become modules with explicit public class methods. `DiffSummarizer` calls them directly:

```ruby
per_file_summaries = BatchRunner.summarize_chunks(parsed_chunks, client:, model:, worker_count:)
combined = combine(per_file_summaries, client:, model:)
```

```ruby
content: FallbackBuilder.fallback_summary(diff, chunks: parsed_chunks)
```

The dependency is visible at the call site rather than implicit through `extend`.

### `ConfigLoader` — compact pattern

`yaml_behavior_config` and `env_behavior_overrides` replace the `.tap do |result|` pattern with direct hash construction followed by `.compact`:

```ruby
def self.yaml_behavior_config(merged)
  git = lookup_key(merged, 'git') || {}
  {
    model: present_or_nil(lookup_key(merged, 'model').to_s),
    candidates: safe_integer(lookup_key(merged, 'candidates')),
    base_branch: present_or_nil(lookup_key(git, 'base_branch').to_s),
    no_copy: as_boolean(lookup_key(merged, 'no_copy')),
    auto_split: as_boolean(lookup_key(merged, 'auto_split')),
    diff_summary_workers: safe_integer(lookup_key(merged, 'diff_summary_workers'))
  }.compact
end
```

Same pattern for `env_behavior_overrides`. No new class introduced.

---

## 5. Test Cleanup

**Delete (dead or duplicate):**
- `spec/lib/services/ollama_client_spec.rb` — no corresponding source file
- `spec/lib/services/clipboard_spec.rb` — duplicate of `spec/lib/services/helpers/clipboard_spec.rb`
- `spec/lib/services/interactive_prompt_spec.rb` — duplicate of `spec/lib/services/helpers/interactive_prompt_spec.rb`
- `spec/lib/services/message_generator_support_spec.rb` — replaced by three new focused specs

**Add:**
- `spec/lib/flows/flow_base_spec.rb`
- `spec/lib/services/git/commit/auto_split_coordinator_spec.rb`
- `spec/lib/services/message_generation/message_cleaner_spec.rb`
- `spec/lib/services/message_generation/message_validator_spec.rb`
- `spec/lib/services/message_generation/commit_normalizer_spec.rb`

**Update:**
- `spec/lib/flows/commit_flow_spec.rb` — for coordinator delegation
- `spec/lib/flows/changelog_flow_spec.rb` (if exists) — for FlowBase inheritance
- `spec/lib/services/google_client_spec.rb` (if exists) — remove private method access

---

## 6. What Does Not Change

- `bin/commiti` — CLI interface unchanged
- `ConfigLoader.load` public contract — same keys, same precedence
- `BaseFlow#run` public interface
- All flow entry points (`flow.run`)
- `PromptBuilder`, `TextGenerationStyle`, `GitReader`, `GitWriter`, `DiffParser`, `ChangeGrouping`, `GroupEditor`, `PrCreator`, `PrOpener`, `ChangelogBuilder`, `MessagePresenter`, `InteractivePrompt`, `TerminalUI`, `Spinner`, `Clipboard` — no changes

---

## File Change Summary

| Action | Path |
|--------|------|
| New | `lib/flows/flow_base.rb` |
| New | `lib/services/git/commit/auto_split_coordinator.rb` |
| New | `lib/services/message_generation/message_cleaner.rb` |
| New | `lib/services/message_generation/message_validator.rb` |
| New | `lib/services/message_generation/commit_normalizer.rb` |
| Modified | `lib/flows/base_flow.rb` |
| Modified | `lib/flows/commit_flow.rb` |
| Modified | `lib/flows/changelog_flow.rb` |
| Modified | `lib/services/message_generator.rb` |
| Modified | `lib/services/google_client.rb` |
| Modified | `lib/services/diff_summarization/diff_summarizer.rb` |
| Modified | `lib/services/diff_summarization/batch_runner.rb` |
| Modified | `lib/services/diff_summarization/fallback_builder.rb` |
| Modified | `lib/services/helpers/config_loader.rb` |
| Modified | `lib/commiti.rb` |
| Deleted | `lib/services/message_generator_support.rb` |
| New spec | `spec/lib/flows/flow_base_spec.rb` |
| New spec | `spec/lib/services/git/commit/auto_split_coordinator_spec.rb` |
| New spec | `spec/lib/services/message_generation/message_cleaner_spec.rb` |
| New spec | `spec/lib/services/message_generation/message_validator_spec.rb` |
| New spec | `spec/lib/services/message_generation/commit_normalizer_spec.rb` |
| Deleted spec | `spec/lib/services/message_generator_support_spec.rb` |
| Deleted spec | `spec/lib/services/ollama_client_spec.rb` |
| Deleted spec | `spec/lib/services/clipboard_spec.rb` |
| Deleted spec | `spec/lib/services/interactive_prompt_spec.rb` |
