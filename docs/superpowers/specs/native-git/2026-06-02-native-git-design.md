---
name: native-git
description: Frictionless daily workflow — git hooks integration, branch-to-issue injection, commiti amend, dry-run
metadata:
  type: project
---

# Direction 3: Native Git — Frictionless Daily Workflow

**Date:** 2026-06-02
**Status:** Design

## Problem

Commiti is a separate command you have to remember to run. A developer's muscle memory is `git add . && git commit -m "..."` — not `commiti`. Even enthusiastic adopters skip it when they're in flow.

Additionally:
- Branch names like `feature/JIRA-123-add-login` contain issue references that never make it into commit messages or PR descriptions.
- There's no way to fix a bad generated message on the last commit without re-running the full flow.
- No dry-run mode makes it hard to evaluate the gem's output quality before committing to it.

## Goals

- Running `git commit` automatically invokes commiti (opt-in via `commiti --install-hook`).
- Branch names with issue patterns (JIRA, GitHub, Linear) automatically inject a reference into commit messages and PR descriptions.
- `commiti amend` re-generates the message for the last commit without touching the diff.
- `commiti --dry-run` shows what would be generated and exits without committing or copying.

## Non-Goals

- Replacing `git commit` entirely or wrapping the git binary.
- Enforcing commit message format via a `commit-msg` hook (that's a linter's job, not commiti's).
- Any network calls during `git commit` if the user is offline.

---

## Architecture

### Git Hook Integration

**`commiti --install-hook`** writes a `prepare-commit-msg` Git hook to `.git/hooks/prepare-commit-msg`. This hook is invoked by Git before the commit message editor opens.

The hook script:

```bash
#!/usr/bin/env bash
# Written by commiti --install-hook
# Remove this file or run `commiti --uninstall-hook` to disable.

COMMIT_SOURCE="$2"

# Only run for normal commits (not merges, squashes, or amends with -c)
if [ -n "$COMMIT_SOURCE" ]; then
  exit 0
fi

commiti --type commit --no-copy --hook-mode --output-file "$1"
exit $?
```

`--hook-mode` is a new internal flag that:
- Skips the interactive "commit this message?" prompt (the hook writes to the file; Git shows the editor)
- Skips clipboard copy (controlled by `--no-copy`)
- Writes the generated message to the path passed as `$1` (the commit message file) instead of stdout

**`commiti --uninstall-hook`** removes `.git/hooks/prepare-commit-msg` if it was written by commiti (checks for the `# Written by commiti` comment). Errors if the file exists but wasn't written by commiti — prints a warning instead of deleting.

**Hook safety:** If commiti fails (non-zero exit), the hook exits non-zero and Git aborts the commit with an error message that includes commiti's stderr output. The user can override by running `git commit --no-verify` to skip hooks.

**`--install-hook` options:**
- `--global` — installs to the global Git hook template directory (`git config core.hooksPath` or `~/.git-templates/hooks/`) so all new repos get it automatically.
- Default (no flag) — installs to the current repo's `.git/hooks/`.

### Branch-to-Issue Injection

`IssueDetector` is a new service that parses the current branch name and extracts issue references:

```
lib/services/git/issue_detector.rb
```

**Patterns detected:**

| Pattern | Example branch | Extracted |
|---|---|---|
| JIRA-style | `feature/PROJ-123-login` | `PROJ-123` |
| GitHub `#NNN` | `fix/123-null-pointer` | `#123` |
| Linear | `feature/abc-123-add-auth` | `ABC-123` |

`IssueDetector.detect(branch_name)` returns `nil` or a string like `"PROJ-123"`.

**Injection behavior:**

For commit flow: if an issue reference is detected and the generated message does not already contain it, append a trailer line:

```
feat(auth): add JWT refresh token rotation

Refs: PROJ-123
```

The trailer is appended after the body (or after the subject if there's no body), separated by a blank line. This follows the Git trailer convention and is compatible with GitHub's "closes" syntax if the pattern is `#NNN`.

For PR flow: inject the reference into the PR description body (in the Motivation section, or as a footer line if no Motivation section exists).

**Config:** Issue injection is on by default. Opt out via:

```yaml
issue_injection: false
```

Or override the detected reference manually with `--issue PROJ-456` CLI flag.

### `commiti amend`

A new `AmendFlow` class (subclass of `BaseFlow`) that re-generates the commit message for `HEAD` without touching the diff.

**Behavior:**
1. Read the staged diff of HEAD: `git diff HEAD~1 HEAD`
2. Run through the normal generation pipeline (context build → generate → select)
3. Prompt: "Amend HEAD with this message? [y/N]"
4. On yes: run `git commit --amend --file=<tmpfile> --no-edit` (no interactive editor)
5. On no: print message and exit (no changes made)

**CLI:**
```
commiti --amend
# or
commiti --type amend
```

`AmendFlow` reuses all of `BaseFlow`'s pipeline. The only difference from `CommitFlow` is that `collect_diff` reads `HEAD~1..HEAD` instead of the staged index, and `finalize` runs `git commit --amend` instead of `git commit`.

**Safety:** If HEAD is a merge commit, `AmendFlow` prints a warning and exits without generating.

### Dry-Run Mode

`--dry-run` is a new flag accepted by all flow types. When set:
- The full generation pipeline runs (config load, diff collect, context build, generate)
- Output is printed to stdout as normal
- No clipboard copy happens
- No commit, PR creation, or file write happens
- Exit code 0

This lets users evaluate output quality and prompt tuning without side effects.

**Config equivalent:** `COMMITI_DRY_RUN=true` env var (useful in CI to preview changelog without publishing).

---

## CLI Changes

```
commiti --install-hook [--global]    # install prepare-commit-msg hook
commiti --uninstall-hook             # remove hook written by commiti
commiti --amend                      # re-generate message for HEAD
commiti --dry-run                    # generate and print, no side effects
commiti --issue PROJ-123             # override detected issue reference
```

All new flags are parsed in `bin/commiti` and routed to the appropriate flow or flow option.

---

## Data Flow

### Hook path
```
git commit
  └─ Git invokes .git/hooks/prepare-commit-msg
       └─ commiti --type commit --no-copy --hook-mode --output-file <path>
            └─ CommitFlow#run (hook variant)
                 └─ writes message to <path>
                 └─ exits 0
  └─ Git opens editor with pre-filled message
  └─ User saves → commit created
```

### Amend path
```
commiti --amend
  └─ AmendFlow#run
       └─ GitReader.head_diff   (new: git diff HEAD~1 HEAD)
       └─ FlowContextBuilder.build(...)
       └─ MessageGenerator → select_message
       └─ InteractivePrompt.ask_yes_no("Amend HEAD?")
       └─ GitWriter.amend_head!(message)   (new)
```

---

## GitWriter / GitReader Extensions

**`GitReader.head_diff`** — runs `git diff HEAD~1 HEAD` and returns the unified diff string.

**`GitWriter.amend_head!(message)`** — writes `message` to a temp file and runs `git commit --amend --file=<tmpfile>`. Raises on non-zero exit.

**`GitWriter.hook_installed?(scope:)`** — returns true if `.git/hooks/prepare-commit-msg` exists and contains the commiti marker comment. Used by `--install-hook` to prevent double-installation.

---

## Error Handling

- `--install-hook` fails with a clear message if `.git` does not exist in cwd.
- `--install-hook` fails if the hook file already exists and was not written by commiti (to avoid clobbering a custom hook).
- Hook script exits 0 if commiti is not on PATH (graceful degradation: commit proceeds without pre-fill).
- `AmendFlow` exits with error if HEAD is a merge commit. If staged changes are present, it prints a warning ("You have staged changes; amend will only update the message, not include them") and prompts to continue or abort.
- Dry-run mode never raises on generation failure — prints the error and exits with code 1.

---

## Testing

- `IssueDetector` unit tests: JIRA pattern, GitHub `#NNN`, Linear, no match returns nil, multiple matches returns first.
- Hook installation: test `GitWriter.write_hook!` writes correct file content; test `--install-hook` errors on existing non-commiti hook.
- `AmendFlow` integration test uses a real temp git repo: make a commit, run AmendFlow with a stubbed generator, verify `git log -1` has the new message.
- Dry-run: test that `--dry-run` produces output but makes no commits and does not copy to clipboard. Verify by checking git log and clipboard mock.
- Issue injection: test that a branch named `feature/PROJ-123-login` with a generated message not containing `PROJ-123` gets the `Refs: PROJ-123` trailer appended.

---

## Backwards Compatibility

- All new flags are opt-in. No existing behavior changes.
- `--install-hook` is idempotent: running it twice on the same repo is a no-op with a notice.
- The `prepare-commit-msg` hook only runs for standard commits — it checks `$2` (COMMIT_SOURCE) and exits 0 for merges, squashes, and fixups to avoid interfering with those workflows.
- `issue_injection: false` in config disables the feature entirely for repos that manage issue references differently.
