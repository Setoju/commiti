# SUMMARY — Upgrade CLI visuals

## What was built
- Added a reusable `TerminalUI` helper for compact status symbols, ANSI-safe color formatting, headers, and separators.
- Upgraded spinner output to be clearer in both TTY and non-TTY modes, with explicit success/failure/info status lines.
- Improved readability of commit flow output (auto-split notices, group headers, skip notices).
- Improved readability of presenter/execution notices (summarization, clipboard result, commit outcome, editor validation notices).

## Files changed
- `lib/services/helpers/terminal_ui.rb` (new)
- `lib/commiti.rb`
- `lib/services/helpers/spinner.rb`
- `spec/lib/services/spinner_spec.rb`
- `spec/lib/services/terminal_ui_spec.rb` (new)
- `lib/services/message_presenter.rb`
- `lib/flows/commit_flow.rb`
- `lib/services/git/commit/commit_staging.rb`
- `lib/services/git/commit/commit_execution.rb`

## Verification run
- ✅ `bundle exec rspec` (87 examples, 0 failures)
- ✅ `gem build commiti.gemspec` (build succeeded)
- ✅ `bundle exec ruby -Ilib bin/commiti --help` (CLI help renders)
- ⚠️ `bundle exec rubocop` reports pre-existing baseline offenses in unrelated files (no new feature-specific lint regressions introduced)

## How to test/use
1. Run `bundle exec ruby -Ilib bin/commiti --type commit` in a repo with staged changes.
2. Observe improved stage/status readability during spinner steps and candidate display.
3. Optionally run with `--auto-split` and `--candidates 2` to see group headers and candidate selection presentation.
4. Pipe output to non-TTY context to confirm plain-text fallback remains readable.
