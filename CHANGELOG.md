# Changelog

All notable changes to this project are documented in this file.

## [1.3.0] - 2026-05-19

### Added
- New `--auto-split` commit mode that automatically groups connected staged changes into multiple atomic commits.
- New config toggle `COMMITI_AUTO_SPLIT` (also documented in `.env.example`).
- Connected-change grouping engine (`Commiti::ChangeGrouping`) based on logical file stem and namespace proximity.
- End-to-end integration coverage for auto-split behavior, including:
  - grouped multi-commit history generation,
  - restaging behavior when a later grouped commit is skipped,
  - nested namespace grouping.

### Changed
- Commit flow now supports grouped execution in auto-split mode:
  - unstages current index,
  - stages files per detected group,
  - generates one message per group,
  - asks confirmation per grouped commit,
  - restages remaining changes if flow is interrupted/skipped.
- Flow context now includes computed `change_groups` metadata from parsed diff chunks.
- Git writer gained explicit staging helpers for grouped execution (`stage_all!`, `unstage_all!`, `stage_files!`).
- Commit execution now returns explicit outcomes (`:committed` / `:skipped`) used by grouped flow control.

### Docs
- README updated with `--auto-split` usage and behavior notes.

## [1.2.3] - 2026-05-18

### Baseline
- Google AI based commit/PR generation flow.
- Conventional commit normalization and validation.
- PR compare/MR URL generation with payload capping.
- Large-diff clipping and summarization pipeline with batching/fallback.
