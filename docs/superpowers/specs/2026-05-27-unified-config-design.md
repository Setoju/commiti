# Unified Config Design

**Date:** 2026-05-27
**Status:** Approved

## Problem

Non-secret behavior flags (`model`, `candidates`, `base_branch`, `no_copy`, `auto_split`, `diff_summary_workers`) currently live exclusively as env vars. This creates friction for both solo developers (who must set them per shell/project) and teams (who cannot version-control them). There is also no global default file — every project starts from hardcoded defaults.

## Goal

Move all non-secret behavior settings into `.commiti.yml`, support a global `~/.commiti.yml` for personal defaults, and keep env vars only for secrets and CI overrides.

## Out of Scope

- Multi-provider AI support (separate feature)
- Named config profiles
- Secrets in YAML

---

## Config Schema

Both `~/.commiti.yml` (global) and `.commiti.yml` (project) accept the same schema. All keys are optional — omitted keys fall through to the next layer.

```yaml
model: gemma-4-31b-it
candidates: 1
auto_split: false
no_copy: false
diff_summary_workers: 4

git:
  base_branch: main

text_generation:
  commit:
    subject_case: lowercase
  pr:
    sections:
      - name: Overview
        guidance: Summarize the change in one paragraph.
```

The `text_generation` block is unchanged from the current schema.

---

## Precedence Order

Highest to lowest priority:

1. **CLI flags** — `--candidates`, `--no-copy`, `--base` (always win)
2. **Env var overrides** — `COMMITI_MODEL`, `COMMITI_AUTO_SPLIT`, etc. (CI / secrets escape hatch)
3. **Project `.commiti.yml`** — checked in, team-shared
4. **Global `~/.commiti.yml`** — personal defaults, applies to every repo
5. **Hardcoded defaults** — current fallback values in `ConfigLoader`

Secrets (`GOOGLE_API_KEY`, `COMMITI_GITHUB_TOKEN`, `COMMITI_GITLAB_TOKEN`, `COMMITI_GITBUCKET_TOKEN`) are never read from YAML.

The `COMMITI_CONFIG` env var continues to point to the project config path (not the global file).

---

## Implementation

All changes are contained within `lib/services/helpers/config_loader.rb`.

### 1. Global file discovery

On load, check `~/.commiti.yml`. If present, parse it with the same safe YAML loader already used for project config.

### 2. Deep merge

Merge: global → project (deep merge). Top-level scalar keys (`model`, `candidates`, etc.) use shallow merge. The `text_generation` hash uses recursive merge so a project can override just `commit.subject_case` without wiping global `pr.sections`. Array values (e.g., `pr.sections`) are replaced entirely by the more specific layer — they are not appended.

### 3. Env var mapping

After YAML merge is resolved, env vars override their corresponding keys. The existing mapping table runs last instead of being the only source of truth for behavior flags.

No changes to `bin/commiti`, flows, or any other service — they consume the resolved config object, which is fully built before they run.

---

## Testing

- Unit tests on `ConfigLoader` covering all five precedence layers.
- Test that a project key overrides the same global key.
- Test that a project omitting a key inherits the global value.
- Test that an env var overrides both YAML files.
- Test that secrets are never read from YAML.
- Test deep merge: project `text_generation.commit.subject_case` override does not wipe global `text_generation.pr.sections`.
