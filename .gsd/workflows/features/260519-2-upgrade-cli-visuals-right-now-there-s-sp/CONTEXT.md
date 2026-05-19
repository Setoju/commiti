# CONTEXT — Upgrade CLI visuals

## Feature description
Improve Commiti CLI readability so users can quickly scan progress and generated output. The current spinner shows activity, but status, section transitions, and candidate output are visually dense and hard to parse.

## Proposed key decisions
1. **Visual approach:** add lightweight ANSI styling (color + symbols + section headers) with no new gem dependency.
2. **Terminal compatibility:** keep plain, clean text in non-TTY environments; only enhance formatting for interactive terminals.
3. **Scope of changes:** update only presentation-layer modules (`Spinner`, `MessagePresenter`, and minimal flow print lines) without changing generation logic.
4. **Backwards safety:** preserve existing behavior and prompts (candidate selection, commit confirmation, clipboard flow), only improve readability of emitted text.

## Gray areas surfaced
- How far to go visually (minimal status polish vs richer boxed/sectioned output).
- Whether to add color only for statuses or also for message/candidate framing.
- Whether to show extra context metadata (e.g., candidate count, group progress) in a structured format.
- How strict tests should be around formatting details vs behavior.

## Scope boundaries
### In scope
- Improve spinner completion/failure line readability.
- Improve message/candidate rendering readability.
- Improve key info banners/notices printed during commit/PR flows.
- Add/update tests for output behavior.

### Out of scope
- Changing prompt generation, model requests, or diff summarization logic.
- Reworking commit/PR business flow semantics.
- Adding theme/config system for custom colors.
- Replacing terminal IO libraries or introducing heavy UI frameworks.
