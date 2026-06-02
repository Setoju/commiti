---
name: first-mile
description: Remove barriers to adoption — commiti init wizard, multi-provider AI support, commiti doctor
metadata:
  type: project
---

# Direction 1: First Mile — Remove Barriers to Adoption

**Date:** 2026-06-02
**Status:** Design

## Problem

Two barriers kill adoption before the user generates their first message:

1. **Provider lock-in (A):** The gem requires a Google API key. Developers who already have OpenAI, Anthropic, or a local Ollama instance must sign up for another service just to try it.
2. **Setup friction (D):** No guided setup. A new user must read the README, find the right env var names, create a `.commiti.yml` manually, then discover what `--type` flags exist. That's too much before first value.

## Goals

- A developer with any supported API key can go from `gem install commiti` to their first generated commit message in under 60 seconds.
- The gem works with Google AI, OpenAI, Anthropic, and Ollama without changing anything except config.
- A `commiti doctor` command diagnoses common misconfigurations and tells the user exactly what to fix.

## Non-Goals

- Supporting every AI provider ever. The four named above cover the vast majority of developer credentials.
- A GUI or web-based setup flow.
- Changing how generation, prompts, or output quality work — this direction is purely about provider abstraction and onboarding.

---

## Architecture

### Provider Abstraction

The current `GoogleClient` is directly instantiated in `BaseFlow`. The refactor introduces a `Client` interface and a `ClientFactory` that reads config and returns the right implementation.

```
lib/services/
  clients/
    base_client.rb          # abstract interface: #generate(system:, user:, model:, **opts)
    google_client.rb        # moved from services/google_client.rb
    openai_client.rb        # new
    anthropic_client.rb     # new
    ollama_client.rb        # new
  client_factory.rb         # resolves provider from config, returns client instance
```

`BaseClient` defines one required method:

```ruby
def generate(system:, user:, model:, temperature: nil, timeout_seconds: nil, **opts)
  raise NotImplementedError
end
```

Each client implements it against its own API. Callers (`BaseFlow`, `DiffSummarizer`) receive a client from `ClientFactory` and call `#generate` — they never know which provider they're talking to.

**`ClientFactory.build(config:)`** reads `config[:provider]` (default: `'google'`) and instantiates the matching client. Raises `Commiti::ConfigError` if the provider is unknown or the required key is missing.

### Config Changes

Add `provider` as a first-class config key:

```yaml
provider: openai          # google | openai | anthropic | ollama
model: gpt-4o             # provider-specific model name
```

Default remains `google` so all existing setups are unaffected.

Provider API keys remain env-only:

```
GOOGLE_API_KEY / GEMINI_API_KEY    (existing)
OPENAI_API_KEY                     (new)
ANTHROPIC_API_KEY                  (new)
OLLAMA_BASE_URL                    (new, default: http://localhost:11434)
```

`ConfigLoader` maps each provider to its key env var. `ClientFactory` validates presence at build time.

### `commiti init` Wizard

A new `InitFlow` class (not a subclass of `BaseFlow`) drives an interactive terminal wizard. It uses a thin `WizardPrompt` wrapper around TTY::Reader so inputs can be stubbed in tests without real terminal I/O:

**Steps:**
1. Detect if current directory is a Git repo. Warn and continue if not.
2. Ask: "Which AI provider do you have a key for?" (select list: Google, OpenAI, Anthropic, Ollama local)
3. Prompt for the API key (or base URL for Ollama). Validate it's non-empty.
4. Ask: "Write to global config (`~/.commiti.yml`) or project config (`.commiti.yml`)?" Default: global.
5. Check if target config file exists. If so, ask: "Update existing file or skip?"
6. Write `provider:` and `model:` to the chosen YAML file.
7. Write the API key based on config scope:
   - **Project config** → write `KEY=value` to `.env` in cwd. Before writing, check if `.env` appears in `.gitignore`. If not, ask: "Add `.env` to `.gitignore`?" Default: yes.
   - **Global config** → detect shell profile (`~/.zshrc` if it exists, otherwise `~/.bashrc`) and append `export KEY=value`. Print a reminder to re-source the file or open a new terminal.
8. Print a success summary with the first command to run: `commiti` or `commiti --type pr`.

The wizard never stores the API key in any YAML file — only in `.env` (project) or the shell profile (global).

### `commiti doctor`

A diagnostic command that prints a structured health check:

```
commiti doctor
```

Checks (in order):
1. **Git repo**: is cwd a git repo?
2. **Config file**: does `~/.commiti.yml` or `.commiti.yml` exist? Which provider is set?
3. **API key**: is the required env var for the configured provider present and non-empty?
4. **Reachability**: send a minimal test request to the provider API. For Google/OpenAI/Anthropic: a 1-token generate call. For Ollama: `GET {OLLAMA_BASE_URL}/api/tags` (model list endpoint). Reports latency or error.
5. **Model**: is the configured model name recognized by the provider? (Where checkable without a full request.)
6. **Git remote**: for PR flow, is a remote configured?

Each check prints `[OK]`, `[WARN]`, or `[FAIL]` with a one-line explanation and fix suggestion on failure.

`commiti doctor` exits with code 0 if all checks pass, code 1 if any FAIL.

---

## CLI Entry Point

`commiti init` and `commiti doctor` are bare subcommands, not `--type` values. `bin/commiti` checks `ARGV[0]` before option parsing and dispatches immediately:

```
commiti init       # runs InitFlow
commiti doctor     # runs DoctorFlow
```

Both bypass `BaseFlow` entirely and route directly to `InitFlow.new.run` or `DoctorFlow.new.run`. All other invocations fall through to the existing `--type` option parser.

---

## Data Flow

```
bin/commiti
  └─ ARGV[0] == 'init'   → InitFlow.run      (bypasses option parser)
  └─ ARGV[0] == 'doctor' → DoctorFlow.run    (bypasses option parser)
  └─ OptionParser → CommitFlow / PrFlow / ChangelogFlow
       └─ BaseFlow#run
            └─ ClientFactory.build(config:)   ← NEW
                 └─ GoogleClient | OpenAIClient | AnthropicClient | OllamaClient
```

---

## Provider Implementation Notes

### OpenAI (`openai_client.rb`)
- Uses `https://api.openai.com/v1/chat/completions`
- Maps `system:` → `{ role: 'system', content: system }`, `user:` → `{ role: 'user', content: user }`
- Reads response from `choices[0].message.content`
- No extra gems required (HTTParty already present)

### Anthropic (`anthropic_client.rb`)
- Uses `https://api.anthropic.com/v1/messages`
- Sets `anthropic-version: 2023-06-01` header
- Maps `system:` to the top-level `system` field, `user:` to `messages[0]`
- Reads response from `content[0].text`

### Ollama (`ollama_client.rb`)
- Uses `{OLLAMA_BASE_URL}/api/chat` (default `http://localhost:11434`)
- Same message mapping as OpenAI chat format
- No API key required; skips key validation
- `commiti doctor` checks that the base URL is reachable

---

## Error Handling

- `ClientFactory.build` raises `Commiti::ConfigError` with a human-readable message that names the missing env var.
- Each client raises a descriptive `RuntimeError` on non-2xx responses, mirroring the existing `GoogleClient` pattern.
- `commiti init` catches `Interrupt` (Ctrl-C) and exits cleanly with "Setup cancelled."
- `commiti doctor` never raises — it catches all errors per check and reports them as `[FAIL]`.

---

## Testing

- `ClientFactory` unit tests: returns correct client class for each provider string; raises on unknown provider; raises on missing key.
- Each new client has a unit test that stubs HTTP and verifies the request body shape and response parsing.
- `InitFlow` tests use a temp directory and stub `WizardPrompt` inputs — verify the correct YAML keys are written, `.env` contains the key (project path), and shell profile contains `export KEY=value` (global path).
- `DoctorFlow` tests stub each check individually and verify exit code and output.
- Existing `BaseFlow` tests are unaffected; they can stub `ClientFactory.build` to return the existing `GoogleClient` double.

---

## Migration / Backwards Compatibility

- `GoogleClient` moves to `lib/services/clients/google_client.rb`; all references updated in one step (no deprecation shim).
- Default provider remains `google`; existing configs without a `provider:` key continue to work without changes.
- All existing env vars (`GOOGLE_API_KEY`, `GEMINI_API_KEY`) continue to work.
