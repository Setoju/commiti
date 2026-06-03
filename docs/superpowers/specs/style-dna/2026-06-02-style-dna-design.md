---
name: style-dna
description: Repo-aware output quality — analyze commit history to match project style, auto-scope inference
metadata:
  type: project
---

# Direction 2: Style DNA — Repo-Aware Output Quality

**Date:** 2026-06-02
**Status:** Design

## Problem

Generated commit messages are technically valid but stylistically foreign. A project that always uses `fix(api):` scopes, two-sentence bodies, and lowercase subjects gets `feat: Update authentication logic` — and the developer edits it every time.

The gem never looks at the repository's existing commit history, so every generation starts from the same generic prompt. The output is consistent with the Conventional Commits spec but inconsistent with the project's voice.

## Goals

- Generated messages match the project's existing scope conventions, subject length, body style, and type distribution without any manual configuration.
- Auto-infer conventional commit scopes from changed file paths so the developer never has to think about `(auth)` vs `(api)` vs `(ui)`.
- Teams can freeze a style snapshot in `.commiti.yml` so new contributors get the team style even before they've built up local history.
- Works on repos with no prior conventional commits (degrades gracefully to current behavior).

## Non-Goals

- Rewriting history or linting existing commits.
- Learning from commit bodies (only subjects, types, and scopes are analyzed).
- Replacing the configurable `text_generation` YAML block — this feature enriches it dynamically.

---

## Architecture

### New Service: `StyleAnalyzer`

```
lib/services/style_analyzer.rb
```

`StyleAnalyzer.analyze(lookback: 50)` reads the last N conventional-commit-formatted subjects from the current branch's history and returns a `StyleProfile` struct:

```ruby
StyleProfile = Struct.new(
  :dominant_types,        # e.g. ["feat", "fix", "refactor"] sorted by frequency
  :scope_usage_rate,      # Float 0.0–1.0: fraction of commits that use a scope
  :common_scopes,         # e.g. ["api", "auth", "ui"] sorted by frequency
  :median_subject_length, # Integer: median character count of subjects
  :uses_body,             # Boolean: >30% of sampled commits have a body
  :subject_case,          # "lowercase" | "uppercase" | "mixed" (majority vote)
  keyword_init: true
)
```

**Analysis steps:**
1. Call `GitReader.recent_commits(n: lookback)` — already exists as `commits_in_range` and can be extended.
2. Filter to lines matching `COMMIT_PREFIX_PATTERN` from `MessageGenerator`.
3. Extract type, scope (if present), subject text, and whether a body follows.
4. Compute statistics listed above.
5. Return `StyleProfile`. If fewer than 5 matching commits found, return `nil` (no style inference).

`StyleAnalyzer` never writes to disk. It is called once per flow run and its result is passed into `FlowContextBuilder`.

### Scope Inference: `ScopeInferrer`

```
lib/services/scope_inferrer.rb
```

`ScopeInferrer.infer(files:, common_scopes:)` maps changed file paths to a conventional commit scope string.

**Algorithm:**
1. Extract path segments from each changed file (e.g., `app/services/auth/token_service.rb` → `['app', 'services', 'auth', ...]`).
2. For each segment, check if it appears in `common_scopes` from the `StyleProfile`. First match wins.
3. If no match from history, use a built-in path-to-scope map:
   - `auth`, `authentication`, `sessions` → `auth`
   - `api`, `controllers` → `api`
   - `models`, `db`, `migrations` → `db`
   - `spec`, `test` → `test`
   - `config` → `config`
   - `lib` → scope from the next segment
4. If multiple scopes inferred across files and they're all the same → use it. If mixed → omit scope (don't guess).
5. Returns a scope string (e.g., `"auth"`) or `nil`.

The inferred scope is passed to `PromptBuilder` as a hint, not a hard constraint.

### Prompt Injection

`FlowContextBuilder.build` gains a `style_profile:` keyword. When present (non-nil), `PromptBuilder.build` appends a **Style Context** block to the system prompt:

```
Style context from this repository's commit history:
- Dominant types used: feat, fix, refactor
- Scope usage: 78% of commits use a scope
- Most common scopes: api, auth, ui
- Typical subject length: ~52 characters
- Body usage: yes (most commits include a body)
- Subject case: lowercase after prefix
- Suggested scope for this diff: auth

Match this style unless the diff clearly calls for a different type or scope.
```

The style context is labeled as **contextual guidance, not a rule**, to avoid conflicting with the strict system prompt constraints. It is placed after the existing style guidance block.

### Config Integration

Add two optional keys to `.commiti.yml`:

```yaml
style_learning: true        # default: true (opt-out available)
style_lookback: 50          # commits to analyze, default: 50, max: 200
```

A project can also freeze a style snapshot to share with contributors:

```yaml
text_generation:
  commit:
    style_snapshot:
      dominant_types: [feat, fix, chore]
      scope_usage_rate: 0.85
      common_scopes: [api, auth, ui]
      median_subject_length: 52
      uses_body: false
      subject_case: lowercase
```

When `style_snapshot` is present in YAML, `StyleAnalyzer` is skipped and the frozen profile is used instead. This is the team-distribution path: one developer runs analysis and commits the snapshot; everyone else gets consistent style without needing the git history to match.

---

## Data Flow

```
BaseFlow#run
  └─ StyleAnalyzer.analyze(lookback: N)   ← NEW (skipped if style_learning: false)
       └─ GitReader.recent_commits(n: N)
       └─ returns StyleProfile | nil
  └─ ScopeInferrer.infer(files:, common_scopes:)   ← NEW
  └─ FlowContextBuilder.build(..., style_profile:, inferred_scope:)
       └─ PromptBuilder.build(..., style_profile:, inferred_scope:)
            └─ appends Style Context block to system prompt
```

`StyleAnalyzer` only runs for `:commit` flow type. PR flow does not use it (PR descriptions don't follow commit conventions).

---

## GitReader Extension

Add `GitReader.recent_subjects(n:)` that returns an array of raw commit subject lines (the first line only) from the last N commits on the current branch:

```ruby
def self.recent_subjects(n: 50)
  output = run_git("log --no-merges --format=%s -n #{n}")
  output.lines.map(&:chomp).reject(&:empty?)
end
```

This is the only new Git operation required.

---

## Error Handling

- `StyleAnalyzer.analyze` rescues all exceptions and returns `nil` on failure (e.g., no git history, empty repo). Generation continues with the current generic prompt.
- `ScopeInferrer.infer` returns `nil` on any error. The prompt omits the scope hint rather than guessing.
- If `style_snapshot` YAML is malformed, `ConfigLoader` ignores the snapshot key and falls back to live analysis.

---

## Testing

- `StyleAnalyzer` unit tests use a real temp git repo (consistent with existing test conventions) seeded with a controlled commit history. Verify correct extraction of types, scopes, subject lengths, body usage.
- `ScopeInferrer` unit tests cover: exact match in common_scopes, built-in map fallback, mixed-scope returns nil, empty file list returns nil.
- `PromptBuilder` tests: when `style_profile:` is provided, the system prompt includes the Style Context block. When nil, prompt is unchanged from current behavior.
- `StyleAnalyzer.analyze` returns nil when fewer than 5 matching commits found — tested with a 3-commit repo.

---

## Backwards Compatibility

- `style_learning` defaults to `true` but adding `style_learning: false` to `.commiti.yml` or setting `COMMITI_STYLE_LEARNING=false` restores the current prompt with no style injection.
- Repos with no conventional commits are unaffected: `StyleAnalyzer` returns `nil`, prompt is unchanged.
- The `text_generation.commit.subject_case` config key continues to override the inferred `subject_case` from history (explicit config always wins).
