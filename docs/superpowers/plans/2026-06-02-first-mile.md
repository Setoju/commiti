# First Mile — Remove Barriers to Adoption

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce multi-provider AI client abstraction (Google, OpenAI, Anthropic, Ollama), an interactive `commiti init` setup wizard, and a `commiti doctor` diagnostic command so any developer can go from `gem install commiti` to first generated message in under 60 seconds.

**Architecture:** Phase 1 adds `BaseClient`, moves `GoogleClient` to `lib/services/clients/`, creates three new provider clients, and wires them through `ClientFactory` so `BaseFlow` is provider-agnostic. Phase 2 adds `InitFlow` (8-step interactive wizard that writes config YAML and credentials to `.env` or shell profile). Phase 3 adds `DoctorFlow` (6 health checks, structured output, exit-code contract). All three phases are strictly sequential — each must have a passing test suite before the next begins.

**Tech Stack:** Ruby 3+, RSpec, HTTParty (already present), TTY::Reader (already present), YAML

---

## File Map

### Phase 1 — Provider Abstraction

| Action | Path |
|--------|------|
| Create | `lib/services/clients/base_client.rb` |
| Create | `lib/services/clients/google_client.rb` |
| Delete | `lib/services/google_client.rb` |
| Create | `lib/services/clients/openai_client.rb` |
| Create | `lib/services/clients/anthropic_client.rb` |
| Create | `lib/services/clients/ollama_client.rb` |
| Create | `lib/services/client_factory.rb` |
| Modify | `lib/services/helpers/config_loader.rb` |
| Modify | `lib/flows/base_flow.rb` |
| Modify | `lib/commiti.rb` |
| Modify | `bin/commiti` |
| Create | `spec/lib/services/clients/google_client_spec.rb` |
| Create | `spec/lib/services/clients/openai_client_spec.rb` |
| Create | `spec/lib/services/clients/anthropic_client_spec.rb` |
| Create | `spec/lib/services/clients/ollama_client_spec.rb` |
| Create | `spec/lib/services/client_factory_spec.rb` |
| Modify | `spec/lib/services/config_loader_spec.rb` |

### Phase 2 — Init Wizard

| Action | Path |
|--------|------|
| Modify | `lib/services/helpers/interactive_prompt.rb` |
| Create | `lib/flows/init_flow.rb` |
| Modify | `lib/commiti.rb` |
| Modify | `bin/commiti` |
| Create | `spec/lib/flows/init_flow_spec.rb` |
| Modify | `spec/lib/services/helpers/interactive_prompt_spec.rb` |

### Phase 3 — Doctor

| Action | Path |
|--------|------|
| Modify | `lib/services/git/git_reader.rb` |
| Create | `lib/flows/doctor_flow.rb` |
| Modify | `lib/commiti.rb` |
| Modify | `bin/commiti` |
| Create | `spec/lib/flows/doctor_flow_spec.rb` |

---

## Phase 1 — Provider Abstraction

### Task 1: Add `Commiti::ConfigError` and `BaseClient`

**Files:**
- Modify: `lib/commiti.rb`
- Create: `lib/services/clients/base_client.rb`

- [ ] **Step 1: Add `ConfigError` to `lib/commiti.rb`**

At the very top of `lib/commiti.rb`, before all `require_relative` lines, add:

```ruby
module Commiti
  class ConfigError < StandardError; end
end
```

- [ ] **Step 2: Create `lib/services/clients/base_client.rb`**

```ruby
# frozen_string_literal: true

module Commiti
  class BaseClient
    def generate(system:, user:, model:, temperature: nil, timeout_seconds: nil, **opts)
      raise NotImplementedError, "#{self.class} must implement #generate"
    end
  end
end
```

- [ ] **Step 3: Add require to `lib/commiti.rb`**

After the `ConfigError` definition block, add as the first `require_relative`:

```ruby
require_relative 'services/clients/base_client'
```

- [ ] **Step 4: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all existing tests pass (no behaviour change).

- [ ] **Step 5: Commit**

```bash
git add lib/commiti.rb lib/services/clients/base_client.rb
git commit -m "feat: add ConfigError and BaseClient abstract interface"
```

---

### Task 2: Move `GoogleClient` to `lib/services/clients/`

**Files:**
- Create: `lib/services/clients/google_client.rb`
- Create: `spec/lib/services/clients/google_client_spec.rb`
- Delete: `lib/services/google_client.rb`
- Modify: `lib/commiti.rb`

- [ ] **Step 1: Write tests for `GoogleClient`**

Create `spec/lib/services/clients/google_client_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::GoogleClient do
  describe '#generate' do
    let(:client) { described_class.new(config: { google_api_key: 'test-key' }) }
    let(:success_body) do
      { candidates: [{ content: { parts: [{ text: 'feat: add login' }] } }] }.to_json
    end
    let(:ok_response) do
      instance_double(HTTParty::Response, success?: true, body: success_body)
    end

    it 'returns extracted text on success' do
      allow(described_class).to receive(:post).and_return(ok_response)
      expect(client.generate(system: 'sys', user: 'usr', model: 'gemma-4-31b-it')).to eq('feat: add login')
    end

    it 'raises when API key is missing' do
      bare = described_class.new(config: {})
      allow(described_class).to receive(:post).and_return(ok_response)
      expect { bare.generate(system: 's', user: 'u', model: 'gemma-4-31b-it') }
        .to raise_error(/Google API key is missing/)
    end

    it 'raises with error detail on non-2xx response' do
      error_body = { error: { message: 'quota exceeded' } }.to_json
      bad = instance_double(HTTParty::Response, success?: false, code: 429, body: error_body)
      allow(described_class).to receive(:post).and_return(bad)
      expect { client.generate(system: 's', user: 'u', model: 'm') }
        .to raise_error(/quota exceeded/)
    end
  end
end
```

- [ ] **Step 2: Run tests — they should pass already (class exists at old path)**

```bash
bundle exec rspec spec/lib/services/clients/google_client_spec.rb
```

Expected: PASS (spec_helper loads commiti which loads the existing GoogleClient). This test documents the interface and will continue to pass after the move.

- [ ] **Step 3: Create `lib/services/clients/google_client.rb`**

Copy the full content of `lib/services/google_client.rb` to `lib/services/clients/google_client.rb`, with one change: add `< BaseClient` to the class definition:

```ruby
# frozen_string_literal: true

require 'httparty'
require 'json'
require 'uri'

module Commiti
  class GoogleClient < BaseClient
    include HTTParty

    base_uri 'https://generativelanguage.googleapis.com'
    DEFAULT_MODEL = 'gemma-4-31b-it'
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_TIMEOUT_SECONDS = 180
    DEFAULT_OPEN_TIMEOUT_SECONDS = 10

    def initialize(config: Commiti::ConfigLoader.load)
      @config = config || {}
    end

    def generate(system:, user:, api_key: nil, model: nil, temperature: nil, timeout_seconds: nil, open_timeout_seconds: nil, **opts)
      settings = request_settings(
        api_key: api_key,
        model: model,
        temperature: temperature,
        timeout_seconds: timeout_seconds,
        open_timeout_seconds: open_timeout_seconds
      )
      response = generate_content(system: system, user: user, settings: settings)
      unless response.success?
        detail = extract_error(response.body)
        message = "Google AI error: #{response.code}"
        message = "#{message} - #{detail}" unless detail.empty?
        raise message
      end
      extract_generated_content(response.body)
    end

    private

    def normalize_model(model)
      value = model.to_s.strip
      normalized = value.sub(%r{\Amodels/}, '')
      normalized.empty? ? DEFAULT_MODEL : normalized
    end

    def normalize_api_key(value)
      key = value.to_s.strip
      return key unless key.empty?

      raise 'Google API key is missing. Set GOOGLE_API_KEY (or GEMINI_API_KEY) in your environment.'
    end

    def normalize_numeric(value, fallback)
      return fallback if value.nil? || value.to_s.strip.empty?

      yield(value)
    rescue ArgumentError
      fallback
    end

    def extract_error(body)
      parsed = JSON.parse(body.to_s)
      error = parsed['error']
      return error['message'].to_s.strip if error.is_a?(Hash)
      return error.to_s.strip unless error.nil?

      ''
    rescue JSON::ParserError
      ''
    end

    def extract_content(parsed)
      parts = parsed.dig('candidates', 0, 'content', 'parts')
      return '' unless parts.is_a?(Array)

      parts.map { |part| part['text'].to_s }.join.strip
    end

    def request_settings(api_key:, model:, temperature:, timeout_seconds:, open_timeout_seconds:)
      {
        api_key: normalize_api_key(api_key || @config[:google_api_key]),
        model: normalize_model(model || @config[:model]),
        temperature: normalize_numeric(temperature || @config[:temperature], DEFAULT_TEMPERATURE) { |raw| Float(raw) },
        timeout_seconds: normalize_numeric(timeout_seconds || @config[:timeout_seconds], DEFAULT_TIMEOUT_SECONDS) { |raw| Integer(raw) },
        open_timeout_seconds: normalize_numeric(open_timeout_seconds || @config[:open_timeout_seconds],
                                                DEFAULT_OPEN_TIMEOUT_SECONDS) { |raw| Integer(raw) }
      }
    end

    def extract_generated_content(body)
      parsed = JSON.parse(body.to_s)
      content = extract_content(parsed)
      raise 'Google AI error: response did not include generated text' if content.empty?

      content
    rescue JSON::ParserError => e
      raise "Google AI error: invalid JSON response (#{e.message})"
    end

    def generate_content(system:, user:, settings:)
      self.class.post(
        "/v1beta/models/#{URI.encode_www_form_component(settings[:model])}:generateContent",
        query: { key: settings[:api_key] },
        headers: { 'Content-Type' => 'application/json' },
        timeout: settings[:timeout_seconds],
        open_timeout: settings[:open_timeout_seconds],
        body: request_body(system: system, user: user, settings: settings).to_json
      )
    end

    def request_body(system:, user:, settings:)
      {
        systemInstruction: { parts: [{ text: system.to_s }] },
        generationConfig: { temperature: settings[:temperature] },
        contents: [{ role: 'user', parts: [{ text: user.to_s }] }]
      }
    end
  end
end
```

- [ ] **Step 4: Update `lib/commiti.rb` — swap the require**

Change:
```ruby
require_relative 'services/google_client'
```
To:
```ruby
require_relative 'services/clients/google_client'
```

- [ ] **Step 5: Delete the old file**

```bash
git rm lib/services/google_client.rb
```

- [ ] **Step 6: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all pass. `Commiti::GoogleClient` now loads from the new path; class name and constants are unchanged.

- [ ] **Step 7: Commit**

```bash
git add lib/commiti.rb lib/services/clients/google_client.rb spec/lib/services/clients/google_client_spec.rb
git commit -m "refactor: move GoogleClient to lib/services/clients/ with BaseClient inheritance"
```

---

### Task 3: Add `provider` key to `ConfigLoader`

**Files:**
- Modify: `lib/services/helpers/config_loader.rb`
- Modify: `spec/lib/services/config_loader_spec.rb`

- [ ] **Step 1: Write failing tests**

Add to `spec/lib/services/config_loader_spec.rb` inside `describe '.load'`:

```ruby
describe 'provider config' do
  it 'defaults provider to google' do
    config = described_class.load(env: {})
    expect(config[:provider]).to eq('google')
  end

  it 'reads provider from YAML' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.commiti.yml'), "provider: openai\n")
      config = described_class.load(env: {}, cwd: dir)
      expect(config[:provider]).to eq('openai')
    end
  end

  it 'reads provider from COMMITI_PROVIDER env var' do
    config = described_class.load(env: { 'COMMITI_PROVIDER' => 'anthropic' })
    expect(config[:provider]).to eq('anthropic')
  end

  it 'env var overrides YAML provider' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.commiti.yml'), "provider: openai\n")
      config = described_class.load(env: { 'COMMITI_PROVIDER' => 'ollama' }, cwd: dir)
      expect(config[:provider]).to eq('ollama')
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/services/config_loader_spec.rb -e "provider config"
```

Expected: FAIL — `config[:provider]` is nil.

- [ ] **Step 3: Implement `provider` in `ConfigLoader`**

In `lib/services/helpers/config_loader.rb`:

Add `provider: 'google'` as the first key in `DEFAULT_CONFIG`:

```ruby
DEFAULT_CONFIG = {
  provider: 'google',
  google_api_key: nil,
  # ... rest unchanged
}.freeze
```

Add to `yaml_behavior_config` (inside the returned hash):

```ruby
provider: present_or_nil(lookup_key(merged, 'provider').to_s),
```

Add to `env_behavior_overrides` (inside the returned hash):

```ruby
provider: present_or_nil(env.fetch('COMMITI_PROVIDER', nil)),
```

- [ ] **Step 4: Run config tests**

```bash
bundle exec rspec spec/lib/services/config_loader_spec.rb
```

Expected: all pass.

- [ ] **Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/services/helpers/config_loader.rb spec/lib/services/config_loader_spec.rb
git commit -m "feat: add provider key to ConfigLoader (YAML + COMMITI_PROVIDER env, default: google)"
```

---

### Task 4: Create `OpenAIClient`

**Files:**
- Create: `lib/services/clients/openai_client.rb`
- Create: `spec/lib/services/clients/openai_client_spec.rb`
- Modify: `lib/commiti.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/lib/services/clients/openai_client_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::OpenAIClient do
  let(:client) { described_class.new(config: {}) }
  let(:success_body) { { choices: [{ message: { content: 'feat: add user auth' } }] }.to_json }
  let(:ok_response) do
    instance_double(HTTParty::Response, success?: true, body: success_body,
                    parsed_response: JSON.parse(success_body))
  end

  describe '#generate' do
    it 'returns text from choices[0].message.content' do
      allow(described_class).to receive(:post).and_return(ok_response)
      expect(client.generate(system: 'sys', user: 'usr', model: 'gpt-4o')).to eq('feat: add user auth')
    end

    it 'sends system and user as chat messages' do
      allow(described_class).to receive(:post) do |_path, opts|
        body = JSON.parse(opts[:body])
        expect(body['messages']).to eq([
          { 'role' => 'system', 'content' => 'my system' },
          { 'role' => 'user', 'content' => 'my user' }
        ])
        ok_response
      end
      client.generate(system: 'my system', user: 'my user', model: 'gpt-4o')
    end

    it 'sets Authorization header with Bearer token' do
      stub_const('ENV', ENV.to_h.merge('OPENAI_API_KEY' => 'sk-abc'))
      allow(described_class).to receive(:post) do |_path, opts|
        expect(opts[:headers]['Authorization']).to eq('Bearer sk-abc')
        ok_response
      end
      client.generate(system: 's', user: 'u', model: 'gpt-4o')
    end

    it 'raises on non-2xx with error detail' do
      error_body = { error: { message: 'invalid api key' } }.to_json
      bad = instance_double(HTTParty::Response, success?: false, code: 401, body: error_body,
                            parsed_response: JSON.parse(error_body))
      allow(described_class).to receive(:post).and_return(bad)
      expect { client.generate(system: 's', user: 'u', model: 'm') }.to raise_error(/invalid api key/)
    end

    it 'raises when response content is empty' do
      empty_body = { choices: [{ message: { content: '' } }] }.to_json
      empty = instance_double(HTTParty::Response, success?: true, body: empty_body,
                              parsed_response: JSON.parse(empty_body))
      allow(described_class).to receive(:post).and_return(empty)
      expect { client.generate(system: 's', user: 'u', model: 'm') }
        .to raise_error(/OpenAI error: response did not include generated text/)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/services/clients/openai_client_spec.rb
```

Expected: FAIL — `Commiti::OpenAIClient` uninitialized constant.

- [ ] **Step 3: Implement `OpenAIClient`**

Create `lib/services/clients/openai_client.rb`:

```ruby
# frozen_string_literal: true

require 'httparty'
require 'json'

module Commiti
  class OpenAIClient < BaseClient
    include HTTParty

    base_uri 'https://api.openai.com'
    DEFAULT_MODEL = 'gpt-4o'
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_TIMEOUT_SECONDS = 180
    DEFAULT_OPEN_TIMEOUT_SECONDS = 10

    def initialize(config: {})
      @config = config || {}
    end

    def generate(system:, user:, model: nil, temperature: nil, timeout_seconds: nil, **opts)
      api_key = ENV.fetch('OPENAI_API_KEY', '').strip
      resolved_model = model || @config[:model] || DEFAULT_MODEL
      resolved_temp  = normalize_float(temperature || @config[:temperature], DEFAULT_TEMPERATURE)
      resolved_timeout = normalize_int(timeout_seconds || @config[:timeout_seconds], DEFAULT_TIMEOUT_SECONDS)

      response = self.class.post(
        '/v1/chat/completions',
        headers: {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{api_key}"
        },
        timeout: resolved_timeout,
        open_timeout: DEFAULT_OPEN_TIMEOUT_SECONDS,
        body: {
          model: resolved_model,
          temperature: resolved_temp,
          messages: [
            { role: 'system', content: system.to_s },
            { role: 'user', content: user.to_s }
          ]
        }.to_json
      )

      unless response.success?
        detail = response.parsed_response.dig('error', 'message').to_s.strip
        msg = "OpenAI error: #{response.code}"
        msg = "#{msg} - #{detail}" unless detail.empty?
        raise msg
      end

      content = response.parsed_response.dig('choices', 0, 'message', 'content').to_s.strip
      raise 'OpenAI error: response did not include generated text' if content.empty?

      content
    end

    private

    def normalize_float(value, fallback)
      return fallback if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def normalize_int(value, fallback)
      return fallback if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      fallback
    end
  end
end
```

- [ ] **Step 4: Add require to `lib/commiti.rb`**

After `require_relative 'services/clients/google_client'`, add:

```ruby
require_relative 'services/clients/openai_client'
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/lib/services/clients/openai_client_spec.rb
```

Expected: all pass.

- [ ] **Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/services/clients/openai_client.rb spec/lib/services/clients/openai_client_spec.rb lib/commiti.rb
git commit -m "feat: add OpenAIClient for chat completions API"
```

---

### Task 5: Create `AnthropicClient`

**Files:**
- Create: `lib/services/clients/anthropic_client.rb`
- Create: `spec/lib/services/clients/anthropic_client_spec.rb`
- Modify: `lib/commiti.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/lib/services/clients/anthropic_client_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::AnthropicClient do
  let(:client) { described_class.new(config: {}) }
  let(:success_body) { { content: [{ text: 'feat: improve error messages' }] }.to_json }
  let(:ok_response) do
    instance_double(HTTParty::Response, success?: true, body: success_body,
                    parsed_response: JSON.parse(success_body))
  end

  describe '#generate' do
    it 'returns text from content[0].text' do
      allow(described_class).to receive(:post).and_return(ok_response)
      expect(client.generate(system: 'sys', user: 'usr', model: 'claude-sonnet-4-6'))
        .to eq('feat: improve error messages')
    end

    it 'sends system as top-level field and user as messages array' do
      allow(described_class).to receive(:post) do |_path, opts|
        body = JSON.parse(opts[:body])
        expect(body['system']).to eq('my system')
        expect(body['messages']).to eq([{ 'role' => 'user', 'content' => 'my user' }])
        ok_response
      end
      client.generate(system: 'my system', user: 'my user', model: 'claude-sonnet-4-6')
    end

    it 'sends anthropic-version header' do
      allow(described_class).to receive(:post) do |_path, opts|
        expect(opts[:headers]['anthropic-version']).to eq('2023-06-01')
        ok_response
      end
      client.generate(system: 's', user: 'u', model: 'm')
    end

    it 'raises on non-2xx with error detail' do
      error_body = { error: { message: 'permission denied' } }.to_json
      bad = instance_double(HTTParty::Response, success?: false, code: 403, body: error_body,
                            parsed_response: JSON.parse(error_body))
      allow(described_class).to receive(:post).and_return(bad)
      expect { client.generate(system: 's', user: 'u', model: 'm') }.to raise_error(/permission denied/)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/services/clients/anthropic_client_spec.rb
```

Expected: FAIL — `Commiti::AnthropicClient` uninitialized constant.

- [ ] **Step 3: Implement `AnthropicClient`**

Create `lib/services/clients/anthropic_client.rb`:

```ruby
# frozen_string_literal: true

require 'httparty'
require 'json'

module Commiti
  class AnthropicClient < BaseClient
    include HTTParty

    base_uri 'https://api.anthropic.com'
    DEFAULT_MODEL = 'claude-sonnet-4-6'
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_TIMEOUT_SECONDS = 180
    DEFAULT_OPEN_TIMEOUT_SECONDS = 10
    MAX_TOKENS = 1024

    def initialize(config: {})
      @config = config || {}
    end

    def generate(system:, user:, model: nil, temperature: nil, timeout_seconds: nil, **opts)
      api_key = ENV.fetch('ANTHROPIC_API_KEY', '').strip
      resolved_model   = model || @config[:model] || DEFAULT_MODEL
      resolved_temp    = normalize_float(temperature || @config[:temperature], DEFAULT_TEMPERATURE)
      resolved_timeout = normalize_int(timeout_seconds || @config[:timeout_seconds], DEFAULT_TIMEOUT_SECONDS)

      response = self.class.post(
        '/v1/messages',
        headers: {
          'Content-Type' => 'application/json',
          'x-api-key' => api_key,
          'anthropic-version' => '2023-06-01'
        },
        timeout: resolved_timeout,
        open_timeout: DEFAULT_OPEN_TIMEOUT_SECONDS,
        body: {
          model: resolved_model,
          max_tokens: MAX_TOKENS,
          temperature: resolved_temp,
          system: system.to_s,
          messages: [{ role: 'user', content: user.to_s }]
        }.to_json
      )

      unless response.success?
        detail = response.parsed_response.dig('error', 'message').to_s.strip
        msg = "Anthropic error: #{response.code}"
        msg = "#{msg} - #{detail}" unless detail.empty?
        raise msg
      end

      content = response.parsed_response.dig('content', 0, 'text').to_s.strip
      raise 'Anthropic error: response did not include generated text' if content.empty?

      content
    end

    private

    def normalize_float(value, fallback)
      return fallback if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def normalize_int(value, fallback)
      return fallback if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      fallback
    end
  end
end
```

- [ ] **Step 4: Add require to `lib/commiti.rb`**

After the OpenAI require, add:

```ruby
require_relative 'services/clients/anthropic_client'
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/lib/services/clients/anthropic_client_spec.rb
```

Expected: all pass.

- [ ] **Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/services/clients/anthropic_client.rb spec/lib/services/clients/anthropic_client_spec.rb lib/commiti.rb
git commit -m "feat: add AnthropicClient for messages API"
```

---

### Task 6: Create `OllamaClient`

**Files:**
- Create: `lib/services/clients/ollama_client.rb`
- Create: `spec/lib/services/clients/ollama_client_spec.rb`
- Modify: `lib/commiti.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/lib/services/clients/ollama_client_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::OllamaClient do
  let(:client) { described_class.new(config: {}) }
  let(:success_body) { { message: { content: 'feat: cache results' } }.to_json }
  let(:ok_response) do
    instance_double(HTTParty::Response, success?: true, body: success_body,
                    parsed_response: JSON.parse(success_body))
  end

  before { stub_const('ENV', ENV.to_h.merge('OLLAMA_BASE_URL' => 'http://localhost:11434')) }

  describe '#generate' do
    it 'returns text from message.content' do
      allow(described_class).to receive(:post).and_return(ok_response)
      expect(client.generate(system: 'sys', user: 'usr', model: 'llama3.2')).to eq('feat: cache results')
    end

    it 'sends stream: false' do
      allow(described_class).to receive(:post) do |_url, opts|
        expect(JSON.parse(opts[:body])['stream']).to be(false)
        ok_response
      end
      client.generate(system: 's', user: 'u', model: 'llama3.2')
    end

    it 'posts to OLLAMA_BASE_URL/api/chat' do
      allow(described_class).to receive(:post) do |url, _opts|
        expect(url).to eq('http://localhost:11434/api/chat')
        ok_response
      end
      client.generate(system: 's', user: 'u', model: 'llama3.2')
    end

    it 'raises on non-2xx' do
      bad = instance_double(HTTParty::Response, success?: false, code: 500,
                            body: 'internal error', parsed_response: 'internal error')
      allow(described_class).to receive(:post).and_return(bad)
      expect { client.generate(system: 's', user: 'u', model: 'm') }.to raise_error(/Ollama error: 500/)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/services/clients/ollama_client_spec.rb
```

Expected: FAIL — `Commiti::OllamaClient` uninitialized constant.

- [ ] **Step 3: Implement `OllamaClient`**

Create `lib/services/clients/ollama_client.rb`:

```ruby
# frozen_string_literal: true

require 'httparty'
require 'json'

module Commiti
  class OllamaClient < BaseClient
    include HTTParty

    DEFAULT_MODEL = 'llama3.2'
    DEFAULT_TEMPERATURE = 0.2
    DEFAULT_TIMEOUT_SECONDS = 180
    DEFAULT_OPEN_TIMEOUT_SECONDS = 10
    DEFAULT_BASE_URL = 'http://localhost:11434'

    def initialize(config: {})
      @config = config || {}
      @base_url = ENV.fetch('OLLAMA_BASE_URL', DEFAULT_BASE_URL).strip
    end

    def generate(system:, user:, model: nil, temperature: nil, timeout_seconds: nil, **opts)
      resolved_model   = model || @config[:model] || DEFAULT_MODEL
      resolved_temp    = normalize_float(temperature || @config[:temperature], DEFAULT_TEMPERATURE)
      resolved_timeout = normalize_int(timeout_seconds || @config[:timeout_seconds], DEFAULT_TIMEOUT_SECONDS)

      response = self.class.post(
        "#{@base_url}/api/chat",
        headers: { 'Content-Type' => 'application/json' },
        timeout: resolved_timeout,
        open_timeout: DEFAULT_OPEN_TIMEOUT_SECONDS,
        body: {
          model: resolved_model,
          stream: false,
          options: { temperature: resolved_temp },
          messages: [
            { role: 'system', content: system.to_s },
            { role: 'user', content: user.to_s }
          ]
        }.to_json
      )

      raise "Ollama error: #{response.code} - #{response.body.to_s.strip}" unless response.success?

      content = response.parsed_response.dig('message', 'content').to_s.strip
      raise 'Ollama error: response did not include generated text' if content.empty?

      content
    end

    private

    def normalize_float(value, fallback)
      return fallback if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      fallback
    end

    def normalize_int(value, fallback)
      return fallback if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      fallback
    end
  end
end
```

- [ ] **Step 4: Add require to `lib/commiti.rb`**

After the Anthropic require, add:

```ruby
require_relative 'services/clients/ollama_client'
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/lib/services/clients/ollama_client_spec.rb
```

Expected: all pass.

- [ ] **Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/services/clients/ollama_client.rb spec/lib/services/clients/ollama_client_spec.rb lib/commiti.rb
git commit -m "feat: add OllamaClient for local inference via Ollama API"
```

---

### Task 7: Create `ClientFactory`

**Files:**
- Create: `lib/services/client_factory.rb`
- Create: `spec/lib/services/client_factory_spec.rb`
- Modify: `lib/commiti.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/lib/services/client_factory_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::ClientFactory do
  describe '.build' do
    context 'google (default)' do
      it 'returns GoogleClient when provider is google' do
        stub_const('ENV', ENV.to_h.merge('GOOGLE_API_KEY' => 'key'))
        expect(described_class.build(config: { provider: 'google' })).to be_a(Commiti::GoogleClient)
      end

      it 'defaults to Google when provider key is absent' do
        stub_const('ENV', ENV.to_h.merge('GOOGLE_API_KEY' => 'key'))
        expect(described_class.build(config: {})).to be_a(Commiti::GoogleClient)
      end
    end

    context 'openai' do
      it 'returns OpenAIClient when OPENAI_API_KEY is set' do
        stub_const('ENV', ENV.to_h.merge('OPENAI_API_KEY' => 'sk-key'))
        expect(described_class.build(config: { provider: 'openai' })).to be_a(Commiti::OpenAIClient)
      end

      it 'raises ConfigError when OPENAI_API_KEY is missing' do
        stub_const('ENV', ENV.to_h.reject { |k, _| k == 'OPENAI_API_KEY' })
        expect { described_class.build(config: { provider: 'openai' }) }
          .to raise_error(Commiti::ConfigError, /OPENAI_API_KEY/)
      end
    end

    context 'anthropic' do
      it 'returns AnthropicClient when ANTHROPIC_API_KEY is set' do
        stub_const('ENV', ENV.to_h.merge('ANTHROPIC_API_KEY' => 'ant-key'))
        expect(described_class.build(config: { provider: 'anthropic' })).to be_a(Commiti::AnthropicClient)
      end

      it 'raises ConfigError when ANTHROPIC_API_KEY is missing' do
        stub_const('ENV', ENV.to_h.reject { |k, _| k == 'ANTHROPIC_API_KEY' })
        expect { described_class.build(config: { provider: 'anthropic' }) }
          .to raise_error(Commiti::ConfigError, /ANTHROPIC_API_KEY/)
      end
    end

    context 'ollama' do
      it 'returns OllamaClient without requiring a key' do
        expect(described_class.build(config: { provider: 'ollama' })).to be_a(Commiti::OllamaClient)
      end
    end

    context 'unknown provider' do
      it 'raises ConfigError' do
        expect { described_class.build(config: { provider: 'fakeprovider' }) }
          .to raise_error(Commiti::ConfigError, /Unknown provider/)
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/services/client_factory_spec.rb
```

Expected: FAIL — `Commiti::ClientFactory` uninitialized constant.

- [ ] **Step 3: Implement `ClientFactory`**

Create `lib/services/client_factory.rb`:

```ruby
# frozen_string_literal: true

module Commiti
  class ClientFactory
    SUPPORTED = %w[google openai anthropic ollama].freeze

    def self.build(config:)
      provider = (config[:provider] || 'google').to_s.strip.downcase

      raise ConfigError, "Unknown provider '#{provider}'. Supported: #{SUPPORTED.join(', ')}" unless SUPPORTED.include?(provider)

      case provider
      when 'openai'
        validate_env!('OPENAI_API_KEY')
        OpenAIClient.new(config: config)
      when 'anthropic'
        validate_env!('ANTHROPIC_API_KEY')
        AnthropicClient.new(config: config)
      when 'ollama'
        OllamaClient.new(config: config)
      else
        GoogleClient.new(config: config)
      end
    end

    def self.validate_env!(key)
      raise ConfigError, "#{key} is not set. Run: commiti init" if ENV.fetch(key, '').strip.empty?
    end
    private_class_method :validate_env!
  end
end
```

- [ ] **Step 4: Add require to `lib/commiti.rb`**

After the Ollama require, add:

```ruby
require_relative 'services/client_factory'
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/lib/services/client_factory_spec.rb
```

Expected: all pass.

- [ ] **Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/services/client_factory.rb spec/lib/services/client_factory_spec.rb lib/commiti.rb
git commit -m "feat: add ClientFactory to resolve and instantiate AI provider clients"
```

---

### Task 8: Wire `ClientFactory` into `BaseFlow` and update `bin/commiti`

**Files:**
- Modify: `lib/flows/base_flow.rb`
- Modify: `bin/commiti`

- [ ] **Step 1: Replace `GoogleClient.new` with `ClientFactory.build` in `BaseFlow`**

In `lib/flows/base_flow.rb`, change:

```ruby
client = Commiti::GoogleClient.new(config: options)
```

To:

```ruby
client = Commiti::ClientFactory.build(config: options)
```

- [ ] **Step 2: Replace the full `bin/commiti` with a provider-agnostic version**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'dotenv/load'
require 'commiti'

options = {
  type: :commit,
  auto_split: false
}

OptionParser.new do |opts|
  opts.banner = <<~BANNER

    Commiti — AI commit & PR generator
    Usage: commiti [options]

  BANNER

  opts.on('--type TYPE', %i[commit pr changelog],
          'Message type: commit, pr, or changelog (default: commit)') do |t|
    options[:type] = t
  end

  opts.on('--base BRANCH', 'Base branch for PR diff (default: main)') do |b|
    options[:base_branch] = b
  end

  opts.on('--no-copy', 'Print output only, skip clipboard copy') do
    options[:no_copy] = true
  end

  opts.on('--candidates N', Integer, 'Number of output candidates to generate (1-5, default: 1)') do |n|
    raise OptionParser::InvalidArgument, 'candidates must be between 1 and 5' unless n.between?(1, 5)

    options[:candidates] = n
  end

  opts.on('--auto-split', 'Auto-group staged changes into multiple connected commits (commit flow only)') do
    options[:auto_split] = true
  end

  opts.on('--range RANGE', 'Git revision range for changelog (e.g. v1.2.0..HEAD)') do |range|
    options[:range] = range
  end

  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
end.parse!

begin
  provider_label = ENV.fetch('COMMITI_PROVIDER', 'google')
  model_label    = ENV.fetch('COMMITI_MODEL', 'default')
  flow_label     = case options[:type]
                   when :pr then 'PR flow'
                   when :changelog then 'Changelog flow'
                   else 'Commit flow'
                   end
  base_label  = options[:type] == :pr ? "Base: #{options[:base_branch] || 'main'}" : nil
  range_label = options[:type] == :changelog ? "Range: #{options[:range] || 'unset'}" : nil
  model_meta  = options[:type] == :changelog ? nil : "Model: #{model_label}"
  meta = [flow_label, "Provider: #{provider_label}", model_meta, base_label, range_label].compact.join(' • ')
  puts Commiti::TerminalUI.banner(title: 'Commiti', subtitle: 'AI commit & PR generator', meta: meta)

  flow = case options[:type]
         when :pr        then Commiti::Flows::PrFlow.new(options: options)
         when :changelog then Commiti::Flows::ChangelogFlow.new(options: options)
         else                 Commiti::Flows::CommitFlow.new(options: options)
         end

  flow.run
rescue Commiti::ConfigError => e
  puts "\nConfiguration error: #{e.message}\n\n"
  exit 1
rescue RuntimeError => e
  puts "\nError: #{e.message}\n\n"
  exit 1
rescue SocketError, Errno::ECONNREFUSED
  puts "\nError: Could not connect to AI provider API. Check network access and DNS resolution.\n\n"
  exit 1
rescue Net::OpenTimeout, Net::ReadTimeout
  puts "\nError: AI provider request timed out. Try again or use a smaller diff.\n\n"
  exit 1
rescue StandardError => e
  puts "\nError: Something went wrong (#{e.class}).\n\n"
  exit 1
end
```

- [ ] **Step 3: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all pass. `BaseFlow` now delegates client creation to `ClientFactory`. Existing specs test private methods that accept `client:` directly — they are unaffected.

- [ ] **Step 4: Commit**

```bash
git add lib/flows/base_flow.rb bin/commiti
git commit -m "feat: wire ClientFactory into BaseFlow, update bin/commiti for multi-provider"
```

---

## Phase 2 — Init Wizard

### Task 9: Add `ask_select` to `InteractivePrompt`

**Files:**
- Modify: `lib/services/helpers/interactive_prompt.rb`
- Modify: `spec/lib/services/helpers/interactive_prompt_spec.rb`

- [ ] **Step 1: Write failing tests**

Add to `spec/lib/services/helpers/interactive_prompt_spec.rb`:

```ruby
describe '.ask_select' do
  it 'returns the chosen option by 1-based number' do
    allow(described_class).to receive(:read_input).and_return('2')
    expect(described_class.ask_select('Pick one', %w[Alpha Beta Gamma])).to eq('Beta')
  end

  it 'loops on invalid input and returns on valid' do
    allow(described_class).to receive(:read_input).and_return('x', '0', '1')
    expect(described_class.ask_select('Pick one', %w[Alpha Beta])).to eq('Alpha')
  end

  it 'returns nil when input is nil (Ctrl-C)' do
    allow(described_class).to receive(:read_input).and_return(nil)
    expect(described_class.ask_select('Pick one', %w[Alpha Beta])).to be_nil
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/services/helpers/interactive_prompt_spec.rb -e "ask_select"
```

Expected: FAIL — `undefined method 'ask_select'`.

- [ ] **Step 3: Add `ask_select` to `InteractivePrompt`**

Add before the final `end` of the `InteractivePrompt` module in `lib/services/helpers/interactive_prompt.rb`:

```ruby
def self.ask_select(question, options)
  puts Commiti::TerminalUI.prompt(question)
  options.each_with_index { |opt, i| puts "  #{Commiti::TerminalUI.muted("#{i + 1}.")} #{opt}" }
  loop do
    input = read_input(Commiti::TerminalUI.muted("Choice [1-#{options.length}]: "))
    return nil if input.nil?

    idx = input.strip.to_i - 1
    return options[idx] if input.strip.match?(/\A\d+\z/) && idx.between?(0, options.length - 1)

    puts Commiti::TerminalUI.status(:warn, "Please type a number between 1 and #{options.length}.")
  end
end
```

- [ ] **Step 4: Run tests**

```bash
bundle exec rspec spec/lib/services/helpers/interactive_prompt_spec.rb
```

Expected: all pass.

- [ ] **Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/services/helpers/interactive_prompt.rb spec/lib/services/helpers/interactive_prompt_spec.rb
git commit -m "feat: add InteractivePrompt.ask_select for numbered menu selection"
```

---

### Task 10: Create `InitFlow`

**Files:**
- Create: `lib/flows/init_flow.rb`
- Create: `spec/lib/flows/init_flow_spec.rb`
- Modify: `lib/commiti.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/lib/flows/init_flow_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'yaml'
require 'fileutils'

RSpec.describe Commiti::Flows::InitFlow do
  let(:tmpdir) { Dir.mktmpdir }
  let(:flow)   { described_class.new }

  after { FileUtils.rm_rf(tmpdir) }

  def stub_prompts(provider_name:, credential:, scope_name:, update_existing: :yes, add_gitignore: :yes)
    allow(Commiti::InteractivePrompt).to receive(:ask_select)
      .with(/provider/i, anything).and_return(provider_name)
    allow(Commiti::InteractivePrompt).to receive(:ask_text)
      .and_return(credential)
    allow(Commiti::InteractivePrompt).to receive(:ask_select)
      .with(/config/i, anything).and_return(scope_name)
    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no)
      .with(/Update/i, anything).and_return(update_existing)
    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no)
      .with(/.gitignore/i, anything).and_return(add_gitignore)
  end

  context 'project config with OpenAI' do
    before do
      Dir.mkdir(File.join(tmpdir, '.git'))
      allow(Dir).to receive(:pwd).and_return(tmpdir)
      stub_prompts(provider_name: 'OpenAI', credential: 'sk-test', scope_name: 'Project (.commiti.yml)')
    end

    it 'writes provider and model to .commiti.yml' do
      flow.run
      config = YAML.safe_load_file(File.join(tmpdir, '.commiti.yml'))
      expect(config['provider']).to eq('openai')
      expect(config['model']).to eq('gpt-4o')
    end

    it 'writes OPENAI_API_KEY to .env' do
      flow.run
      expect(File.read(File.join(tmpdir, '.env'))).to include('OPENAI_API_KEY=sk-test')
    end

    it 'adds .env to .gitignore' do
      flow.run
      expect(File.read(File.join(tmpdir, '.gitignore'))).to include('.env')
    end

    it 'skips .gitignore update when .env is already listed' do
      File.write(File.join(tmpdir, '.gitignore'), ".env\n")
      expect(Commiti::InteractivePrompt).not_to receive(:ask_yes_no).with(/.gitignore/i, anything)
      flow.run
    end

    it 'does not write .env to .gitignore when user declines' do
      stub_prompts(provider_name: 'OpenAI', credential: 'sk-key',
                   scope_name: 'Project (.commiti.yml)', add_gitignore: nil)
      flow.run
      gitignore = File.join(tmpdir, '.gitignore')
      expect(File.exist?(gitignore) ? File.read(gitignore) : '').not_to include('.env')
    end
  end

  context 'global config with Google AI' do
    let(:global_config_path) { File.join(tmpdir, 'global_commiti.yml') }
    let(:shell_profile_path) { File.join(tmpdir, '.zshrc') }

    before do
      FileUtils.touch(shell_profile_path)
      allow(Dir).to receive(:pwd).and_return(tmpdir)
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with('~/.commiti.yml').and_return(global_config_path)
      allow(File).to receive(:expand_path).with('~/.zshrc').and_return(shell_profile_path)
      stub_prompts(provider_name: 'Google AI', credential: 'my-key', scope_name: 'Global (~/.commiti.yml)')
    end

    it 'writes provider and model to global config' do
      flow.run
      config = YAML.safe_load_file(global_config_path)
      expect(config['provider']).to eq('google')
    end

    it 'appends export KEY=value to shell profile' do
      flow.run
      expect(File.read(shell_profile_path)).to include('export GOOGLE_API_KEY=my-key')
    end

    it 'does not create .env for global config' do
      flow.run
      expect(File.exist?(File.join(tmpdir, '.env'))).to be(false)
    end
  end

  context 'non-git directory' do
    before do
      allow(Dir).to receive(:pwd).and_return(tmpdir)
      stub_prompts(provider_name: 'OpenAI', credential: 'sk-key', scope_name: 'Project (.commiti.yml)')
    end

    it 'continues without raising' do
      expect { flow.run }.not_to raise_error
    end
  end

  context 'Ctrl-C on provider selection' do
    before { allow(Commiti::InteractivePrompt).to receive(:ask_select).and_return(nil) }

    it 'exits with status 0' do
      expect { flow.run }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/flows/init_flow_spec.rb
```

Expected: FAIL — `Commiti::Flows::InitFlow` uninitialized constant.

- [ ] **Step 3: Implement `InitFlow`**

Create `lib/flows/init_flow.rb`:

```ruby
# frozen_string_literal: true

require 'yaml'

module Commiti
  module Flows
    class InitFlow
      PROVIDERS = {
        'Google AI' => {
          key: 'google', env_var: 'GOOGLE_API_KEY',
          prompt: 'Google API key (GOOGLE_API_KEY)',
          default_model: Commiti::GoogleClient::DEFAULT_MODEL
        },
        'OpenAI' => {
          key: 'openai', env_var: 'OPENAI_API_KEY',
          prompt: 'OpenAI API key (OPENAI_API_KEY)',
          default_model: Commiti::OpenAIClient::DEFAULT_MODEL
        },
        'Anthropic' => {
          key: 'anthropic', env_var: 'ANTHROPIC_API_KEY',
          prompt: 'Anthropic API key (ANTHROPIC_API_KEY)',
          default_model: Commiti::AnthropicClient::DEFAULT_MODEL
        },
        'Ollama (local)' => {
          key: 'ollama', env_var: 'OLLAMA_BASE_URL',
          prompt: 'Ollama base URL (default: http://localhost:11434)',
          default_model: Commiti::OllamaClient::DEFAULT_MODEL
        }
      }.freeze

      def run
        warn_if_not_git_repo

        provider_name = Commiti::InteractivePrompt.ask_select(
          'Which AI provider do you have a key for?', PROVIDERS.keys
        )
        exit(0) if provider_name.nil?
        provider = PROVIDERS[provider_name]

        credential = Commiti::InteractivePrompt.ask_text(provider[:prompt])
        exit(0) if credential.nil?
        credential = credential.strip
        if credential.empty?
          puts Commiti::TerminalUI.status(:fail, 'Value cannot be empty. Setup cancelled.')
          exit(1)
        end

        scope_name = Commiti::InteractivePrompt.ask_select(
          'Write to which config?', ['Global (~/.commiti.yml)', 'Project (.commiti.yml)']
        )
        exit(0) if scope_name.nil?
        global = scope_name.start_with?('Global')

        config_path = global ? File.expand_path('~/.commiti.yml') : File.join(Dir.pwd, '.commiti.yml')

        if File.exist?(config_path)
          answer = Commiti::InteractivePrompt.ask_yes_no("#{config_path} already exists. Update it?", default: :yes)
          write_yaml(config_path, provider[:key], provider[:default_model]) if answer == :yes
        else
          write_yaml(config_path, provider[:key], provider[:default_model])
        end

        if global
          write_to_shell_profile(provider[:env_var], credential)
        else
          write_to_dotenv(provider[:env_var], credential)
          handle_gitignore
        end

        puts "\n#{Commiti::TerminalUI.status(:success, 'Setup complete! Run: commiti')}"
      rescue Interrupt
        puts "\nSetup cancelled."
        exit(0)
      end

      private

      def warn_if_not_git_repo
        return if File.directory?(File.join(Dir.pwd, '.git'))

        puts Commiti::TerminalUI.status(:warn, 'Not a git repo. Continuing anyway.')
      end

      def write_yaml(path, provider_key, model)
        existing = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
        File.write(path, existing.merge('provider' => provider_key, 'model' => model).to_yaml)
        puts Commiti::TerminalUI.status(:success, "Config written to #{path}")
      end

      def write_to_dotenv(env_var, value)
        env_path = File.join(Dir.pwd, '.env')
        line = "#{env_var}=#{value}"
        if File.exist?(env_path)
          content = File.read(env_path)
          if content.match?(/^#{Regexp.escape(env_var)}=/)
            File.write(env_path, content.gsub(/^#{Regexp.escape(env_var)}=.*$/, line))
          else
            File.open(env_path, 'a') { |f| f.puts(line) }
          end
        else
          File.write(env_path, "#{line}\n")
        end
        puts Commiti::TerminalUI.status(:success, 'API key written to .env')
      end

      def handle_gitignore
        gitignore_path = File.join(Dir.pwd, '.gitignore')
        content = File.exist?(gitignore_path) ? File.read(gitignore_path) : ''
        return if content.lines.map(&:strip).include?('.env')

        answer = Commiti::InteractivePrompt.ask_yes_no('Add .env to .gitignore?', default: :yes)
        return unless answer == :yes

        File.open(gitignore_path, 'a') { |f| f.puts('.env') }
        puts Commiti::TerminalUI.status(:success, '.env added to .gitignore')
      end

      def write_to_shell_profile(env_var, value)
        profile = detect_shell_profile
        File.open(profile, 'a') { |f| f.puts("\nexport #{env_var}=#{value}") }
        puts Commiti::TerminalUI.status(:success, "API key exported in #{profile}")
        puts Commiti::TerminalUI.status(:warn, "Run: source #{profile}  (or open a new terminal)")
      end

      def detect_shell_profile
        zshrc = File.expand_path('~/.zshrc')
        return zshrc if File.exist?(zshrc)

        File.expand_path('~/.bashrc')
      end
    end
  end
end
```

- [ ] **Step 4: Add require to `lib/commiti.rb`**

After `require_relative 'flows/pr_flow'`, add:

```ruby
require_relative 'flows/init_flow'
```

- [ ] **Step 5: Run tests**

```bash
bundle exec rspec spec/lib/flows/init_flow_spec.rb
```

Expected: all pass.

- [ ] **Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/flows/init_flow.rb spec/lib/flows/init_flow_spec.rb lib/commiti.rb
git commit -m "feat: add InitFlow — interactive setup wizard for provider config and credentials"
```

---

### Task 11: Wire `commiti init` into `bin/commiti`

**Files:**
- Modify: `bin/commiti`

- [ ] **Step 1: Add ARGV[0] dispatch before `options = {}`**

In `bin/commiti`, add after `require 'commiti'` and before `options = { type: :commit, ... }`:

```ruby
case ARGV[0]
when 'init'
  Commiti::Flows::InitFlow.new.run
  exit(0)
end
```

- [ ] **Step 2: Run full test suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add bin/commiti
git commit -m "feat: wire commiti init as bare subcommand via ARGV[0] dispatch"
```

---

## Phase 3 — Doctor

### Task 12: Add `GitReader.remote_url` and create `DoctorFlow`

**Files:**
- Modify: `lib/services/git/git_reader.rb`
- Create: `lib/flows/doctor_flow.rb`
- Create: `spec/lib/flows/doctor_flow_spec.rb`
- Modify: `lib/commiti.rb`

- [ ] **Step 1: Add `GitReader.remote_url`**

In `lib/services/git/git_reader.rb`, add alongside the other public class methods:

```ruby
def self.remote_url(remote: 'origin')
  output, status = Open3.capture2('git', 'remote', 'get-url', remote)
  status.success? ? output.strip : nil
rescue StandardError
  nil
end
```

- [ ] **Step 2: Write failing tests**

Create `spec/lib/flows/doctor_flow_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Commiti::Flows::DoctorFlow do
  let(:tmpdir) { Dir.mktmpdir }
  let(:flow)   { described_class.new }

  after  { FileUtils.rm_rf(tmpdir) }
  before { allow(Dir).to receive(:pwd).and_return(tmpdir) }

  describe '#run' do
    before do
      allow(flow).to receive(:check_reachability).and_return([:success, 'provider responded (42ms)'])
      allow(flow).to receive(:check_git_remote).and_return([:success, 'origin → git@github.com:u/r.git'])
    end

    context 'all checks pass' do
      before do
        Dir.mkdir(File.join(tmpdir, '.git'))
        File.write(File.join(tmpdir, '.commiti.yml'), "provider: ollama\nmodel: llama3.2\n")
      end

      it 'exits 0' do
        expect { flow.run }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end

      it 'prints a line for each check' do
        expect { flow.run rescue nil }.to output(/git repo/i).to_stdout
      end
    end

    context 'a check fails' do
      it 'exits 1' do
        allow(flow).to receive(:check_reachability).and_return([:fail, 'unreachable'])
        expect { flow.run }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end
    end
  end

  describe '#check_git_repo (private)' do
    it 'returns :success when .git exists' do
      Dir.mkdir(File.join(tmpdir, '.git'))
      level, = flow.send(:check_git_repo)
      expect(level).to eq(:success)
    end

    it 'returns :fail when .git is absent' do
      level, = flow.send(:check_git_repo)
      expect(level).to eq(:fail)
    end
  end

  describe '#check_config_file (private)' do
    it 'returns :success with provider when project config exists' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: openai\n")
      level, msg = flow.send(:check_config_file)
      expect(level).to eq(:success)
      expect(msg).to include('openai')
    end

    it 'returns :warn when no config file found' do
      level, = flow.send(:check_config_file)
      expect(level).to eq(:warn)
    end
  end

  describe '#check_api_key (private)' do
    it 'returns :success when OPENAI_API_KEY is set' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: openai\n")
      stub_const('ENV', ENV.to_h.merge('OPENAI_API_KEY' => 'sk-key'))
      level, = flow.send(:check_api_key)
      expect(level).to eq(:success)
    end

    it 'returns :fail when OPENAI_API_KEY is missing' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: openai\n")
      stub_const('ENV', ENV.to_h.reject { |k, _| k == 'OPENAI_API_KEY' })
      level, msg = flow.send(:check_api_key)
      expect(level).to eq(:fail)
      expect(msg).to include('OPENAI_API_KEY')
    end

    it 'returns :success for ollama (no key needed)' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: ollama\n")
      level, = flow.send(:check_api_key)
      expect(level).to eq(:success)
    end
  end

  describe '#check_model (private)' do
    it 'returns :warn when no model is set' do
      level, = flow.send(:check_model)
      expect(level).to eq(:warn)
    end

    it 'returns :success for a valid google model name' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: google\nmodel: gemini-2.5-flash\n")
      level, = flow.send(:check_model)
      expect(level).to eq(:success)
    end

    it 'returns :warn for a suspicious model name' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: google\nmodel: gpt-4o\n")
      level, = flow.send(:check_model)
      expect(level).to eq(:warn)
    end
  end

  describe '#check_git_remote (private)' do
    it 'returns :success when a remote URL is found' do
      allow(Commiti::GitReader).to receive(:remote_url).and_return('git@github.com:u/r.git')
      level, = flow.send(:check_git_remote)
      expect(level).to eq(:success)
    end

    it 'returns :warn when no remote is configured' do
      allow(Commiti::GitReader).to receive(:remote_url).and_return(nil)
      level, = flow.send(:check_git_remote)
      expect(level).to eq(:warn)
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
bundle exec rspec spec/lib/flows/doctor_flow_spec.rb
```

Expected: FAIL — `Commiti::Flows::DoctorFlow` uninitialized constant.

- [ ] **Step 4: Implement `DoctorFlow`**

Create `lib/flows/doctor_flow.rb`:

```ruby
# frozen_string_literal: true

module Commiti
  module Flows
    class DoctorFlow
      PROVIDER_KEY_MAP = {
        'google'    => %w[GOOGLE_API_KEY GEMINI_API_KEY],
        'openai'    => %w[OPENAI_API_KEY],
        'anthropic' => %w[ANTHROPIC_API_KEY],
        'ollama'    => []
      }.freeze

      def run
        checks = [
          ['Git repo',     *check_git_repo],
          ['Config',       *check_config_file],
          ['API key',      *check_api_key],
          ['Reachability', *check_reachability],
          ['Model',        *check_model],
          ['Git remote',   *check_git_remote]
        ]

        checks.each { |label, level, message| puts Commiti::TerminalUI.status(level, "#{label}: #{message}") }

        exit(checks.any? { |_, level, _| level == :fail } ? 1 : 0)
      end

      private

      def config
        @config ||= Commiti::ConfigLoader.load
      end

      def check_git_repo
        if File.directory?(File.join(Dir.pwd, '.git'))
          [:success, 'current directory is a git repo']
        else
          [:fail, 'not a git repo — run commiti from inside a git repo']
        end
      rescue StandardError => e
        [:fail, e.message]
      end

      def check_config_file
        project = File.join(Dir.pwd, '.commiti.yml')
        global  = File.expand_path('~/.commiti.yml')
        path    = [project, global].find { |p| File.exist?(p) }

        if path
          [:success, "#{path} — provider: #{config[:provider] || 'google'}"]
        else
          [:warn, 'no .commiti.yml found — run: commiti init']
        end
      rescue StandardError => e
        [:fail, e.message]
      end

      def check_api_key
        provider = (config[:provider] || 'google').to_s
        required = PROVIDER_KEY_MAP[provider]

        return [:success, 'no key required for Ollama'] if required&.empty?

        present = required&.find { |var| !ENV.fetch(var, '').strip.empty? }
        if present
          [:success, "#{present} is set"]
        else
          [:fail, "#{required&.join(' or ')} is not set — run: commiti init"]
        end
      rescue StandardError => e
        [:fail, e.message]
      end

      def check_reachability
        client = Commiti::ClientFactory.build(config: config)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        client.generate(system: 'Reply with: ok', user: 'ok', model: config[:model])
        ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        [:success, "provider responded (#{ms}ms)"]
      rescue Commiti::ConfigError => e
        [:fail, e.message]
      rescue StandardError => e
        [:fail, "could not reach provider: #{e.message}"]
      end

      def check_model
        model    = config[:model]
        provider = (config[:provider] || 'google').to_s

        return [:warn, 'no model set — will use provider default'] if model.nil? || model.strip.empty?

        normalized = model.sub(/\Amodels\//, '')
        valid = case provider
                when 'google'    then normalized.start_with?('gemma-', 'gemini-')
                when 'openai'    then normalized.match?(/\A(gpt-|o[134])/)
                when 'anthropic' then normalized.start_with?('claude-')
                else true
                end

        if valid
          [:success, "#{model} looks valid for #{provider}"]
        else
          [:warn, "#{model} may not be a valid #{provider} model — check your config"]
        end
      rescue StandardError => e
        [:fail, e.message]
      end

      def check_git_remote
        url = Commiti::GitReader.remote_url
        if url
          [:success, "origin → #{url}"]
        else
          [:warn, 'no git remote configured (PR flow will fall back to browser-open)']
        end
      rescue StandardError => e
        [:warn, e.message]
      end
    end
  end
end
```

- [ ] **Step 5: Add requires to `lib/commiti.rb`**

After `require_relative 'flows/init_flow'`, add:

```ruby
require_relative 'flows/doctor_flow'
```

- [ ] **Step 6: Run tests**

```bash
bundle exec rspec spec/lib/flows/doctor_flow_spec.rb
```

Expected: all pass.

- [ ] **Step 7: Run full suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/services/git/git_reader.rb lib/flows/doctor_flow.rb spec/lib/flows/doctor_flow_spec.rb lib/commiti.rb
git commit -m "feat: add DoctorFlow with 6 health checks and structured output"
```

---

### Task 13: Wire `commiti doctor` into `bin/commiti`

**Files:**
- Modify: `bin/commiti`

- [ ] **Step 1: Expand the ARGV[0] case to handle both subcommands**

In `bin/commiti`, replace:

```ruby
case ARGV[0]
when 'init'
  Commiti::Flows::InitFlow.new.run
  exit(0)
end
```

With:

```ruby
case ARGV[0]
when 'init'
  Commiti::Flows::InitFlow.new.run
  exit(0)
when 'doctor'
  Commiti::Flows::DoctorFlow.new.run
  exit(0)
end
```

- [ ] **Step 2: Run full test suite**

```bash
bundle exec rspec
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add bin/commiti
git commit -m "feat: wire commiti doctor as bare subcommand via ARGV[0] dispatch"
```
