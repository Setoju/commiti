# Complexity Refactor Design

**Date:** 2026-06-03
**Goal:** Reduce accumulated complexity — remove thin wrappers, collapse redundant layers, fix naming confusion, eliminate duplication. No new features; no behavior change.

---

## Approach

Approach 2 (Consolidation): delete files whose entire purpose is to hold logic that belongs in their single caller. Fixes are bundled in the same pass.

---

## Structural Changes: Files Deleted

7 source files are deleted. Content moves into the file that is the only caller.

| Deleted file | Absorbed into |
|---|---|
| `lib/flows/flow_base.rb` | `lib/flows/base_flow.rb` |
| `lib/services/git/commit/auto_split_coordinator.rb` | `lib/flows/commit_flow.rb` |
| `lib/services/message_generation/commit_normalizer.rb` | `lib/services/message_generator.rb` |
| `lib/services/message_generation/message_cleaner.rb` | `lib/services/message_generator.rb` |
| `lib/services/message_generation/message_validator.rb` | `lib/services/message_generator.rb` |
| `lib/services/changelog_builder.rb` | `lib/flows/changelog_flow.rb` |
| `lib/services/scope_inferrer.rb` | `lib/services/flow_context_builder.rb` |

The `lib/services/message_generation/` directory is removed entirely.

**Net:** 46 source files → 39.

---

## Structural Changes: Logic Relocated (No File Deletion)

**Diff clipping moves from `GitReader` to `DiffParser`.**

`GitReader` currently contains ~160 lines of diff-clipping logic (`clip_diff_context`, `clip_chunks`, `clip_single_chunk`, `partition_chunk_lines`, `append_lines_with_limit`, `append_hunks_with_limit`, `append_partial_hunk`, `append_notice`). This is diff-processing logic, not git-reading logic.

After: `DiffParser` gains a public `clip(diff, max_bytes:)` method. `GitReader#staged_diff` and `#branch_diff` call `DiffParser.clip(filtered_diff, max_bytes: MAX_DIFF_BYTES)` instead of calling the internal clipping methods.

---

## Bug Fixes Bundled In

**1. `CommitFlow#run_auto_split` hardcodes `GoogleClient`**

The auto-split path bypasses `ClientFactory`, breaking all non-Google providers silently.

```ruby
# before
client = Commiti::GoogleClient.new(config: options)

# after
client = Commiti::ClientFactory.build(config: options)
```

**2. Duplicate `COMMIT_PREFIX_PATTERN`**

Identical regex defined independently in `MessageGenerator` and `StyleAnalyzer`. After the merge, `MessageGenerator` owns the constant. `StyleAnalyzer` references `Commiti::MessageGenerator::COMMIT_PREFIX_PATTERN`.

**3. `lookup_key` vs `lookup` naming**

`ConfigLoader` has `lookup_key(hash, key)`; `TextGenerationStyle` has `lookup(hash, key)`. Same logic, different names. `ConfigLoader`'s helper is renamed to `lookup` for consistency. No shared module is created — a 3-line private helper does not warrant extraction.

---

## Detail: `FlowBase` → `BaseFlow`

`FlowBase` (19 lines) holds only `initialize` (calls `ConfigLoader.load` and merges options) and `run_stage` (delegates to `Spinner.run`). These move directly into `BaseFlow`. `BaseFlow` no longer inherits from anything.

`flow_base_spec.rb` is deleted; its coverage moves to `base_flow_spec.rb`.

---

## Detail: `AutoSplitCoordinator` → `CommitFlow`

`AutoSplitCoordinator` takes 9 constructor parameters — nearly all are methods borrowed from `CommitFlow`. Its logic is auto-split orchestration that belongs in the flow it serves.

After the merge, `CommitFlow` gains private methods:
- `run_auto_split` (already exists, is simplified — no more coordinator instantiation)
- `build_split_context(diff:, client:, model:)` — wraps `FlowContextBuilder.build`
- `run_single_group(context:)` — handles the single-group fallback
- `run_grouped(context:, client:, model:)` — handles multi-group flow
- `process_group(group:, index:, total:, client:, model:)` — per-group commit loop
- `group_diff(group)` — one-liner, kept as a named helper for clarity

The 9-parameter constructor disappears. `CommitFlow` grows by ~70 lines but remains a single coherent class.

`auto_split_coordinator_spec.rb` is deleted; coverage moves to `commit_flow_spec.rb`.

---

## Detail: `message_generation/` → `MessageGenerator`

Three modules are included into `MessageGenerator` via `include`:
- `MessageCleaner` — `clean_output` (12 lines of logic)
- `MessageValidator` — `invalid_generation_reason`, `commit_generation_reason`, `pr_generation_reason`
- `CommitNormalizer` — `normalize_commit_message`, `extracted_commit_prefix`, `cleaned_commit_subject`, `inferred_commit_prefix`

After the merge, these become private methods directly in `MessageGenerator`. The `include` statements are removed. The `message_generation/` directory is deleted.

The three specs merge into `message_generator_spec.rb`.

---

## Detail: `ChangelogBuilder` → `ChangelogFlow`

`ChangelogFlow` is 16 lines and delegates everything to `ChangelogBuilder`. After the merge, `ChangelogBuilder`'s `build`, `parse_subject`, and `format_entry` become private class methods directly on `ChangelogFlow`. `TYPE_TITLES` and `TYPE_PATTERN` move as constants on `ChangelogFlow`.

`changelog_builder_spec.rb` is deleted; coverage moves to `changelog_flow_spec.rb`.

---

## Detail: `ScopeInferrer` → `FlowContextBuilder`

`ScopeInferrer.infer` is called in exactly one place: `FlowContextBuilder#infer_scope`. The inferrer's logic (`match_common_scope`, `fallback_scope`, `FALLBACK_SCOPE_MAP`) moves into `FlowContextBuilder` as private helpers.

`scope_inferrer_spec.rb` is deleted; coverage moves to `flow_context_builder_spec.rb`.

---

## Test Strategy

- All tests must remain green after each individual deletion/move.
- Changes are applied one file at a time in this order (lowest coupling first):
  1. `ScopeInferrer` → `FlowContextBuilder`
  2. `ChangelogBuilder` → `ChangelogFlow`
  3. `FlowBase` → `BaseFlow`
  4. Diff clipping → `DiffParser`
  5. `message_generation/*` → `MessageGenerator`
  6. `AutoSplitCoordinator` → `CommitFlow` (includes `GoogleClient` bugfix)
  7. Pattern + naming cleanup (`COMMIT_PREFIX_PATTERN`, `lookup_key` → `lookup`)
- Run `bundle exec rspec` after each step.

---

## What Is Not Changed

- All public interfaces and CLI behavior are preserved exactly.
- `FlowContextBuilder` remains its own file (called from two independent paths).
- `TextGenerationStyle` remains its own file (sanitization logic is non-trivial).
- `DiffSummarizer` and its `batch_runner`/`fallback_builder` sub-files are untouched.
- All client files (`google_client.rb`, `openai_client.rb`, etc.) are untouched.
- `git_reader.rb` loses its clipping methods (they move to `diff_parser.rb`). `diff_parser.rb` gains a public `clip` method. All other git sub-files (`git_writer.rb`, `pr/`, `commit/group_editor.rb`, etc.) are untouched.
