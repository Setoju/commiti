# Codebase Map

Generated: 2026-05-19T14:25:08Z | Files: 59 | Described: 0/59
<!-- gsd:codebase-meta {"generatedAt":"2026-05-19T14:25:08Z","fingerprint":"22ee631b0861e4b00d0a0c36253966592c034172","fileCount":59,"truncated":false} -->

### (root)/
- `.commiti.rb`
- `.env.example`
- `.gitignore`
- `.rspec`
- `.rubocop.yml`
- `CHANGELOG.md`
- `commiti.gemspec`
- `GEM_VERSION_AND_INSTALL.md`
- `Gemfile`
- `LICENSE`
- `README.md`
- `skills-lock.json`

### .github/workflows/
- `.github/workflows/lint.yml`

### bin/
- `bin/commiti`

### lib/
- `lib/commiti.rb`

### lib/flows/
- `lib/flows/base_flow.rb`
- `lib/flows/commit_flow.rb`
- `lib/flows/pr_flow.rb`

### lib/services/
- `lib/services/flow_context_builder.rb`
- `lib/services/google_client.rb`
- `lib/services/message_generator.rb`
- `lib/services/message_presenter.rb`

### lib/services/diff_summarization/
- `lib/services/diff_summarization/batch_runner.rb`
- `lib/services/diff_summarization/diff_summarizer.rb`
- `lib/services/diff_summarization/fallback_builder.rb`

### lib/services/git/
- `lib/services/git/diff_parser.rb`
- `lib/services/git/git_reader.rb`
- `lib/services/git/git_writer.rb`

### lib/services/git/commit/
- `lib/services/git/commit/change_grouping.rb`
- `lib/services/git/commit/commit_execution.rb`
- `lib/services/git/commit/commit_staging.rb`

### lib/services/git/pr/
- `lib/services/git/pr/pr_opener.rb`

### lib/services/helpers/
- `lib/services/helpers/clipboard.rb`
- `lib/services/helpers/config_loader.rb`
- `lib/services/helpers/interactive_prompt.rb`
- `lib/services/helpers/prompt_builder.rb`
- `lib/services/helpers/spinner.rb`
- `lib/services/helpers/terminal_ui.rb`

### spec/
- `spec/spec_helper.rb`

### spec/lib/
- `spec/lib/commiti_cli_integration_spec.rb`
- `spec/lib/commiti_spec.rb`

### spec/lib/flows/
- `spec/lib/flows/base_flow_spec.rb`
- `spec/lib/flows/commit_flow_auto_split_integration_spec.rb`
- `spec/lib/flows/commit_flow_spec.rb`

### spec/lib/services/
- `spec/lib/services/change_grouping_spec.rb`
- `spec/lib/services/clipboard_spec.rb`
- `spec/lib/services/config_loader_spec.rb`
- `spec/lib/services/diff_parser_spec.rb`
- `spec/lib/services/diff_pipeline_integration_spec.rb`
- `spec/lib/services/diff_summarizer_spec.rb`
- `spec/lib/services/git_reader_spec.rb`
- `spec/lib/services/git_writer_spec.rb`
- `spec/lib/services/interactive_prompt_spec.rb`
- `spec/lib/services/message_generator_spec.rb`
- `spec/lib/services/ollama_client_spec.rb`
- `spec/lib/services/pr_opener_spec.rb`
- `spec/lib/services/prompt_builder_spec.rb`
- `spec/lib/services/spinner_spec.rb`
- `spec/lib/services/terminal_ui_spec.rb`
