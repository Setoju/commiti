# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all tests
bundle exec rspec

# Run a single spec file
bundle exec rspec spec/lib/services/config_loader_spec.rb

# Run a single example by description
bundle exec rspec spec/lib/services/config_loader_spec.rb -e "reads model"

# Run the CLI from source
bundle exec ruby -Ilib bin/commiti [options]

# Install dependencies
bundle install
```

There is no linter step configured in the Gemfile scripts, but RuboCop is available:
```bash
bundle exec rubocop
```

## Architecture

The gem has three layers: **flows**, **services**, and a **CLI entry point**.

### Entry point

`bin/commiti` parses CLI options and dispatches to one of three flow classes: `CommitFlow`, `PrFlow`, or `ChangelogFlow`.

### Flows (`lib/flows/`)

`BaseFlow` owns the shared generation pipeline: load config → collect diff → build context → generate candidates → select message → copy to clipboard → finalize. Subclasses override `collect_diff`, `flow_type`, and `finalize`.

- `CommitFlow` — stages changes, generates commit message, optionally auto-splits staged diff into grouped commits with an interactive editor (`GroupEditor`)
- `PrFlow` — reads branch diff, generates PR description, creates PR via provider API or opens prefilled browser URL
- `ChangelogFlow` — reads a git revision range, generates changelog entry

`BaseFlow#initialize` calls `ConfigLoader.load` and merges CLI options on top (CLI wins).

### Config (`lib/services/helpers/config_loader.rb`)

`ConfigLoader.load` resolves settings in this order (lowest → highest priority):
1. `DEFAULT_CONFIG` hardcoded values
2. `~/.commiti.yml` global YAML
3. `.commiti.yml` project YAML (or `COMMITI_CONFIG` path)
4. `COMMITI_*` env var overrides

YAML supports: `model`, `candidates`, `auto_split`, `no_copy`, `diff_summary_workers`, `git.base_branch`, `text_generation`. Secrets (`GOOGLE_API_KEY`, `COMMITI_GITHUB_TOKEN`, etc.) are env-only. `TextGenerationStyle.normalize` validates and sanitizes the `text_generation` subtree before use.

### Context building (`lib/services/flow_context_builder.rb`)

`FlowContextBuilder.build` takes a raw diff and produces: `diff_metadata`, `change_groups`, `summarized_result`, and `prompt`. For large diffs it runs `DiffSummarizer` (async batched summarization with fallback to deterministic summaries on timeout) before building the prompt.

### Google AI client (`lib/services/google_client.rb`)

Single `generate(system:, user:, model:, ...)` method over the Generative Language REST API. Uses `HTTParty`. Model defaults to `gemma-4-31b-it`.

### Message generation (`lib/services/message_generator.rb`)

Calls `GoogleClient#generate`, then runs quality checks and normalizes the result. On a weak first attempt it retries once with tighter constraints. For commit flow it enforces conventional commit format (`feat:`, `fix:`, etc.) and applies subject-case styling from config.

### Git services (`lib/services/git/`)

- `GitReader` — reads staged diff, branch diff, recent commits; applies file-aware clipping for large diffs
- `GitWriter` — runs `git add`, `git commit --file`, staging helpers for grouped commits
- `DiffParser` — splits diffs by file, extracts change metadata
- `git/commit/` — `CommitStaging` (prepare staged state), `CommitExecution` (confirm + commit), `ChangeGrouping` (group files by stem/namespace proximity), `GroupEditor` (interactive regroup)
- `git/pr/` — `RemoteParser`, `PrOpener` (browser URL), `PrCreator` (API-first: GitHub/GitLab/GitBucket)

### Prompt building (`lib/services/helpers/prompt_builder.rb`)

Builds strict system + user prompt pairs for commit and PR modes. PR prompt sections are driven by `text_generation.pr.sections` from config.

## Key conventions

- All classes live in the `Commiti` module; flows in `Commiti::Flows`
- Private helpers in services are `private_class_method` on module-level class methods
- `YAML.safe_load_file` with no permitted classes — config files are declarative only
- Tests use real temp directories for file I/O (no YAML mocking); `verify_partial_doubles: true` is enforced
- `CommitFlow#run_auto_split` always restages remaining changes on error to avoid leaving the index in a partial state
