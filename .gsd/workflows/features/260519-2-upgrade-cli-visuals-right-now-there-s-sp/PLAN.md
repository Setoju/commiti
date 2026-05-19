# PLAN — Upgrade CLI visuals

## Chosen direction
Minimal polish: improve scanability with compact status symbols, subtle ANSI color in TTY, and cleaner section formatting while preserving existing flow semantics.

## Task 1 — Add reusable terminal formatting helper
**Goal:** Centralize ANSI/color/symbol rendering with TTY-safe fallbacks.

**Files**
- `lib/services/helpers/terminal_ui.rb` (new)
- `lib/commiti.rb` (require wiring)

**Changes**
- Add helper methods for:
  - `supports_ansi?`
  - status labels (`success`, `fail`, `info`, `warn`)
  - section/header formatting
  - separator lines
- Ensure non-TTY output remains plain text (no color escape sequences).

**Verification**
- `bundle exec rspec spec/lib/services/spinner_spec.rb`
- quick smoke via local script invocation of helper methods.

---

## Task 2 — Upgrade spinner and stage status output readability
**Goal:** Improve progress line clarity and final status readability.

**Files**
- `lib/services/helpers/spinner.rb`
- `lib/flows/base_flow.rb` (if stage wrapper output needs small adjustment)

**Changes**
- Keep spinner animation behavior intact.
- Improve final lines with clear symbols/status labels and consistent spacing.
- Keep non-TTY branch deterministic and readable.

**Verification**
- `bundle exec rspec spec/lib/services/spinner_spec.rb`

---

## Task 3 — Improve message/candidate rendering and flow notices
**Goal:** Make generated output easier to scan.

**Files**
- `lib/services/message_presenter.rb`
- `lib/flows/commit_flow.rb` (small print-line polish)
- `lib/services/git/commit/commit_staging.rb` (status block polish)
- `lib/services/git/commit/commit_execution.rb` (success/error notice polish)

**Changes**
- Add clearer headers around generated message and candidates.
- Improve copy-to-clipboard and summarization notices with compact status markers.
- Keep prompts and control flow unchanged.

**Verification**
- `bundle exec rspec spec/lib/flows/commit_flow_spec.rb spec/lib/flows/base_flow_spec.rb`

---

## Task 4 — Full verification and workflow summary
**Goal:** Validate the entire feature and document usage.

**Files**
- `.gsd/workflows/features/260519-2-upgrade-cli-visuals-right-now-there-s-sp/SUMMARY.md`
- Optional README touch-up only if user-facing wording changed materially.

**Changes**
- Run full test/build/lint checks.
- Write concise feature summary with changed files and usage/testing notes.

**Verification**
- `bundle exec rspec`
- `bundle exec rubocop`
- `bundle exec ruby -Ilib bin/commiti --help`
