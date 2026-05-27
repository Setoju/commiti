# Commiti

[![Coverage](https://img.shields.io/badge/coverage-90%25-brightgreen)](coverage/index.html) [![RSpec](https://img.shields.io/badge/rspec-passing-brightgreen)](#)

AI-powered commit message and pull request description generator for Git repositories, using Google AI models.

## What It Does

Commiti helps you:

- Generate conventional commit messages from staged changes.
- Generate structured pull request descriptions from branch diffs.
- Review and optionally edit generated commit messages before writing to Git history.
- Open a prefilled PR/MR page in your browser for GitHub, GitLab, or GitBucket (no provider API token required).
- Preserve semantic diff quality on large changes using file-aware clipping that keeps file headers and hunk markers.

## Requirements

- Ruby 3.2+
- Git
- Google AI API key
- A Git repository as your working directory

## Install Dependencies (from source)

```bash
bundle install
```

## CLI Usage

```bash
bundle exec ruby -Ilib bin/commiti [options]
```

Or after gem installation:

```bash
commiti [options]
```

## Configuration

Commiti uses environment variables for secrets and a checked-in project config file for text-generation styling.

Set variables in your shell, CI secret manager, or local `.env` file (in your project):

```dotenv
GOOGLE_API_KEY=your_google_ai_key

# Optional: provider API tokens for API-first PR/MR creation
# COMMITI_GITHUB_TOKEN=your_github_token
# COMMITI_GITLAB_TOKEN=your_gitlab_token
# COMMITI_GITBUCKET_TOKEN=your_gitbucket_token

# Optional overrides (prefer .commiti.yml for these — env vars take precedence when set):
# COMMITI_MODEL=gemma-4-31b-it
# COMMITI_CANDIDATES=1
# COMMITI_BASE_BRANCH=main
# COMMITI_NO_COPY=false
# COMMITI_AUTO_SPLIT=false

# Optional per-project prompt styling (safe YAML, no code execution):
# COMMITI_CONFIG=.commiti.yml
```

`GEMINI_API_KEY` is also accepted as an alias for `GOOGLE_API_KEY`.

You can copy `.env.example` as a starting point.

A global `~/.commiti.yml` sets personal defaults across all repositories. A project `.commiti.yml` overrides the global file for that repo. Env vars override both.

For project-specific wording and structure, add a `.commiti.yml` file at the repo root:

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

The file is parsed with safe YAML loading, and Commiti only accepts declarative styling settings from it.

Your API key is sent directly from your local process to Google's API.
Commiti does not store it and does not proxy requests through any Commiti server.
Never commit `.env` to git.

### Options

- `--type TYPE` where `TYPE` is `commit`, `pr`, or `changelog` (default: `commit`)
- `--base BRANCH` base branch for PR diff (default: `main`)
- `--range RANGE` git revision range for changelog (example: `v1.2.0..HEAD`)
- `--no-copy` print output only, skip clipboard copy
- `--candidates N` generate `N` output candidates (`1`-`5`, default: `1`)
- `--auto-split` auto-group staged changes into multiple connected commits (commit flow only)
- `-h`, `--help` show help

## Shell Completion

### Bash

```bash
source /path/to/commiti/completions/commiti.bash
```

### Zsh

```zsh
fpath=(/path/to/commiti/completions $fpath)
autoload -Uz compinit && compinit
```

## Commit Flow (`--type commit`)

By default, Commiti creates a single commit from staged changes.
Use `--auto-split` to let Commiti group connected file changes into multiple atomic commits.

When auto-split detects multiple groups, Commiti can optionally open a quick group editor so you can move files between groups before committing.

1. Shows `git status --short`.
2. Asks for confirmation before staging (`git add -A`).
3. Ensures there are staged changes.
4. Reads staged diff and generates commit message candidate(s).
   - If the AI draft misses a conventional commit prefix, Commiti auto-normalizes it to a valid conventional subject.
5. If `--candidates` is greater than `1`, shows numbered candidates and asks you to select one.
6. Shows selected message and asks: `Commit with this message? [y/e/N]`
   - `y`: commit now
   - `e`: open editor, then validate and re-confirm
   - `N`: skip commit
7. Writes commit with `git commit --file <tempfile>`.

### Commit Message Validation

- First line must use a conventional commit prefix (e.g. `feat:`, `fix:`).
- First line must be 100 characters or fewer.

### Why `--file` instead of `-m`

Multi-line messages and special characters are safer with `git commit --file`, avoiding shell quoting edge cases.

### Editor Selection

Commit edit mode uses:

1. `VISUAL`
2. `EDITOR`
3. Fallback: `notepad` on Windows, `vi` on non-Windows

## PR Flow (`--type pr`)

1. Reads branch diff: `git diff <base>...HEAD`.
2. Generates PR description with these sections:
   - `## Summary`
   - `## Motivation`
   - `## Changes Made`
   - `## Testing Notes`
3. Attempts to create and open PR/MR:
   - **API-first path** (when token is configured):
     - GitHub/GitBucket: creates PR via provider API and opens the created PR URL.
     - GitLab: creates MR via provider API and opens the created MR URL.
   - **Fallback path** (when no token, provider unsupported, or API call fails):
     - Opens browser with prefilled PR/MR form using query parameters.
     - If the URL would exceed safe browser/provider limits (~1800 characters), Commiti keeps the title and intelligently truncates the description to the longest text that still fits.
4. Asks before opening browser.

## Changelog Flow (`--type changelog`)

1. Reads commits for the provided git range (for example `v1.2.0..HEAD`).
2. Groups commits by conventional commit type into readable sections.
3. Prints a Markdown changelog with short commit hashes.

Commiti can create PRs/MRs via provider APIs when tokens are configured, and always opens the resulting page in your browser.

### Provider API Logic

When you set a provider token in your configuration, Commiti uses an **API-first strategy**:

**Supported Providers:**
- **GitHub** (github.com and GitHub Enterprise): Uses GitHub REST API v3
- **GitLab** (gitlab.com and self-hosted): Uses GitLab API v4
- **GitBucket**: Uses GitHub-compatible API

**Token Configuration:**
```dotenv
COMMITI_GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
COMMITI_GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxxxxxxxxxx
COMMITI_GITBUCKET_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**API Request Flow:**
1. Parses the Git remote URL to extract provider, host, namespace, and repository.
2. Constructs provider-specific API endpoint and authentication headers.
3. Sends HTTP POST request with generated PR title and description.
4. On success (HTTP 2xx): Returns the created PR/MR URL directly.
5. On failure: Falls back to browser prefill with a user-friendly error message explaining why.

**Error Handling:**
- **Missing token**: Falls back to browser prefill. (Info message)
- **Unsupported provider**: Falls back to browser prefill. (Warning message)
- **API error**: Falls back to browser prefill with error details. (Warning message)
- **Redirect handling**: Automatically follows HTTP redirects (301, 302, 307, 308) but aborts if redirected to a different host.
- **Network errors**: Caught and reported with fallback to browser prefill.

**Advantages of API-First:**
- Creates PR/MR immediately without manual form interaction.
- Preserves full description text (no URL length constraints).
- Seamlessly opens the created PR/MR for immediate review and collaboration.
- Gracefully degrades to browser prefill if API is unavailable.

### Diff Context Protocol

When a diff exceeds internal size limits, Commiti clips and summarizes using file-aware rules:

- Keeps full `diff --git` file headers where possible.
- Preserves `@@ ... @@` hunk headers before clipping hunk bodies.
- Includes as many complete files/hunks as fit in the limit, then appends a clipping notice.
- Summarizes large chunks asynchronously and in batches to reduce total LLM round trips.
- Falls back to deterministic file-level summaries if model summarization times out.

This improves semantic quality for AI generation compared with naive truncation.

## Examples

Generate commit message and commit interactively:

```bash
bundle exec ruby -Ilib bin/commiti --type commit
```

Generate multiple commit message candidates and pick one:

```bash
bundle exec ruby -Ilib bin/commiti --type commit --candidates 3
```

Generate PR description against `develop`:

```bash
bundle exec ruby -Ilib bin/commiti --type pr --base develop
```

Print only, do not copy to clipboard:

```bash
bundle exec ruby -Ilib bin/commiti --type pr --no-copy
```

Generate a changelog from a tag range:

```bash
bundle exec ruby -Ilib bin/commiti --type changelog --range v1.2.0..HEAD
```

## Implementation Overview

Main entrypoint and flow orchestration:

- `bin/commiti`: CLI parsing and flow dispatch
- `lib/flows/base_flow.rb`: shared generation pipeline and quality checks
- `lib/flows/commit_flow.rb`: commit-specific staging/edit/commit interactions
- `lib/flows/pr_flow.rb`: PR-specific URL generation/open flow

Core services:

- `lib/services/git_reader.rb`
  - `lib/services/git/git_reader.rb`: Reads staged diff and branch diff, applies file-aware clipping, provides recent commits helper.
  - `lib/services/git/git_writer.rb`: Reads status/staged state, stages (`git add -A`), commits with message file (`git commit --file`), reads branch and origin remote.
  - `lib/services/git/diff_parser.rb`: Parses diff blocks and derives change metadata.
  - `lib/services/git/pr/pr_opener.rb`: Parses GitHub/GitLab/GitBucket remotes, builds provider-specific PR/MR URL, opens browser cross-platform.
- `lib/services/google_client.rb`: Sends generation requests to Google Generative Language API.
- `lib/services/diff_summarization/diff_summarizer.rb`: Orchestrates large-diff summarization and summary combine.
  - `lib/services/diff_summarization/batch_runner.rb`: Runs asynchronous, batched per-file summarization jobs.
  - `lib/services/diff_summarization/fallback_builder.rb`: Builds deterministic summaries when model summarization fails or times out.
- `lib/services/helpers/config_loader.rb`: Loads environment config plus secure project-level text-generation styling.
  - `lib/services/helpers/prompt_builder.rb`: Builds strict system/user prompts for commit and PR modes.
  - `lib/services/helpers/interactive_prompt.rb`: Handles confirmation prompts, candidate selection, editor loop, and commit message validation.
  - `lib/services/helpers/clipboard.rb`: Provides cross-platform clipboard support.
  - `lib/services/helpers/spinner.rb`: Displays a spinner for long-running operations.
- `lib/services/message_generator.rb`: Generates commit and PR messages with quality checks.
- `lib/services/message_presenter.rb`: Presents generated messages to the user.
- `lib/services/flow_context_builder.rb`: Builds the context for different Commiti flows.
- `lib/services/git/commit/commit_staging.rb`: Handles staging changes for a commit.
- `lib/services/git/commit/commit_execution.rb`: Executes the git commit command.

Service loading:

- `lib/commiti.rb` requires all service modules.

## Error Handling

The CLI reports user-friendly errors for common cases such as:

- No changes/staged changes
- Invalid or missing Git data
- Google AI API connectivity/authentication failures
- Summarization timeouts on large diffs (automatically falls back to a deterministic summary and continues)
- Browser open failures

## Notes

- The default model is `gemma-4-31b-it` in `GoogleClient`.
- PR browser URL body payloads are URL-encoded with `URI.encode_www_form`.
- You can tune summarization worker concurrency with `DIFF_SUMMARY_WORKERS`.
