# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::PromptBuilder do
  describe '.build' do
    it 'builds commit prompt with scope overview and raw diff block' do
      prompt = described_class.build(type: :commit, diff: 'diff --git a/a.rb b/a.rb', summarized: false)

      expect(prompt[:system]).to include('Your sole task is to write a Git commit message')
      expect(prompt[:system]).to include('The first line must be 100 characters or fewer.')
      expect(prompt[:user]).to include('Change scope overview:')
      expect(prompt[:user]).to include('- Total files changed: 1')
      expect(prompt[:user]).to include('Here is the git diff:')
      expect(prompt[:user]).to include('```diff')
      expect(prompt[:user]).to include('Write the commit message now')
      expect(prompt[:user]).to include('keep the first line within 100 characters')
    end

    it 'builds pr prompt with summarized section and raw-diff scope overview' do
      prompt = described_class.build(
        type: :pr,
        diff: "### app/a.rb\n- changed",
        summarized: true,
        raw_diff: 'diff --git a/spec/a_spec.rb b/spec/a_spec.rb'
      )

      expect(prompt[:system]).to include('Your sole task is to write a Pull Request description')
      expect(prompt[:user]).to include('Change scope overview:')
      expect(prompt[:user]).to include('- Total files changed: 1')
      expect(prompt[:user]).to include('Here is a structured summary of the git changes')
      expect(prompt[:user]).to include('Write the PR description now')
      expect(prompt[:user]).not_to include('```diff')
    end

    it 'uses passed diff metadata for scope overview' do
      prompt = described_class.build(
        type: :commit,
        diff: "### lib/a.rb\n- changed",
        summarized: true,
        diff_metadata: { files: ['lib/a.rb', 'lib/b.rb'] }
      )

      expect(prompt[:user]).to include('- Total files changed: 2')
      expect(prompt[:user]).to include('- lib/a.rb')
      expect(prompt[:user]).to include('- lib/b.rb')
    end

    it 'renders configurable commit casing and PR sections' do
      style_config = {
        commit: { subject_case: 'uppercase' },
        pr: {
          sections: [
            { name: 'Overview', guidance: 'Summarize the change.' },
            { name: 'Validation', guidance: 'Describe the checks.' }
          ]
        }
      }

      commit_prompt = described_class.build(type: :commit, diff: 'diff --git a/a.rb b/a.rb', style_config: style_config)
      pr_prompt = described_class.build(type: :pr, diff: '### a.rb\n- changed', style_config: style_config)

      expect(commit_prompt[:system]).to include('Capitalize the first alphabetic character in the subject line.')
      expect(pr_prompt[:system]).to include('Include ONLY these sections in this exact order: ## Overview, ## Validation')
      expect(pr_prompt[:system]).to include('## Overview')
      expect(pr_prompt[:system]).to include('## Validation')
      # Guidance is included in the user prompt as an untrusted block
      expect(pr_prompt[:user]).to include('Project-provided guidance (UNTRUSTED')
      expect(pr_prompt[:user]).to include('Overview: Summarize the change.')
      expect(pr_prompt[:user]).to include('Validation: Describe the checks.')
    end
  end
end
