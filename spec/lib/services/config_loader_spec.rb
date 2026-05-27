# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Commiti::ConfigLoader do
  describe '.load' do
    let(:env) { {} }

    it 'returns defaults when environment variables are not set' do
      config = described_class.load(env: env)

      expect(config[:google_api_key]).to be_nil
      expect(config[:github_token]).to be_nil
      expect(config[:gitlab_token]).to be_nil
      expect(config[:gitbucket_token]).to be_nil
      expect(config[:model]).to eq('gemma-4-31b-it')
      expect(config[:candidates]).to eq(1)
      expect(config[:base_branch]).to eq('main')
      expect(config[:no_copy]).to be(false)
      expect(config[:auto_split]).to be(false)
      expect(config[:temperature]).to eq(0.2)
      expect(config[:timeout_seconds]).to eq(180)
      expect(config[:open_timeout_seconds]).to eq(10)
    end

    it 'loads values from environment variables' do
      env.merge!(
        'GOOGLE_API_KEY' => 'key-123',
        'COMMITI_GITHUB_TOKEN' => 'ghp-123',
        'COMMITI_GITLAB_TOKEN' => 'glp-123',
        'COMMITI_GITBUCKET_TOKEN' => 'gbp-123',
        'COMMITI_MODEL' => 'gemini-2.5-flash',
        'COMMITI_CANDIDATES' => '3',
        'COMMITI_BASE_BRANCH' => 'develop',
        'COMMITI_NO_COPY' => 'true',
        'COMMITI_AUTO_SPLIT' => 'true',
        'COMMITI_MODEL_TEMPERATURE' => '0.5',
        'COMMITI_MODEL_TIMEOUT_SECONDS' => '240',
        'COMMITI_MODEL_OPEN_TIMEOUT_SECONDS' => '20'
      )

      config = described_class.load(env: env)

      expect(config[:google_api_key]).to eq('key-123')
      expect(config[:github_token]).to eq('ghp-123')
      expect(config[:gitlab_token]).to eq('glp-123')
      expect(config[:gitbucket_token]).to eq('gbp-123')
      expect(config[:model]).to eq('gemini-2.5-flash')
      expect(config[:candidates]).to eq(3)
      expect(config[:base_branch]).to eq('develop')
      expect(config[:no_copy]).to be(true)
      expect(config[:auto_split]).to be(true)
      expect(config[:temperature]).to eq(0.5)
      expect(config[:timeout_seconds]).to eq(240)
      expect(config[:open_timeout_seconds]).to eq(20)
    end

    it 'accepts GEMINI_API_KEY as a fallback API key variable' do
      env['GEMINI_API_KEY'] = 'gemini-key-123'

      config = described_class.load(env: env)

      expect(config[:google_api_key]).to eq('gemini-key-123')
    end

    it 'falls back to defaults when numeric and boolean values are invalid' do
      env.merge!(
        'COMMITI_CANDIDATES' => 'abc',
        'COMMITI_NO_COPY' => 'wat',
        'COMMITI_AUTO_SPLIT' => 'not-a-bool',
        'COMMITI_MODEL_TEMPERATURE' => 'nan-nope',
        'COMMITI_MODEL_TIMEOUT_SECONDS' => 'oops',
        'COMMITI_MODEL_OPEN_TIMEOUT_SECONDS' => 'oops'
      )

      config = described_class.load(env: env)

      expect(config[:candidates]).to eq(1)
      expect(config[:no_copy]).to be(false)
      expect(config[:auto_split]).to be(false)
      expect(config[:temperature]).to eq(0.2)
      expect(config[:timeout_seconds]).to eq(180)
      expect(config[:open_timeout_seconds]).to eq(10)
    end

    it 'loads secure text generation styling from a project config file' do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, '.commiti.yml')
        File.write(config_path, <<~YAML)
          text_generation:
            commit:
              subject_case: uppercase
            pr:
              sections:
                - name: Overview
                  guidance: Summarize the change.
                - name: Validation
                  guidance: Describe the checks.
        YAML

        config = described_class.load(env: { 'COMMITI_CONFIG' => config_path }, cwd: dir)

        expect(config[:text_generation][:commit][:subject_case]).to eq('uppercase')
        expect(config[:text_generation][:pr][:sections].map { |section| section[:name] }).to eq(%w[Overview Validation])
        expect(config[:text_generation][:pr][:sections].first[:guidance]).to eq('Summarize the change.')
      end
    end

    it 'falls back to defaults when the project config file is malformed' do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, '.commiti.yml')
        File.write(config_path, 'text_generation: [')

        config = described_class.load(env: { 'COMMITI_CONFIG' => config_path }, cwd: dir)

        expect(config[:text_generation][:commit][:subject_case]).to eq('preserve')
        expect(config[:text_generation][:pr][:sections].map do |section|
          section[:name]
        end).to eq(['Summary', 'Motivation', 'Changes Made', 'Testing Notes'])
      end
    end
  end

  describe '.load with YAML behavior config' do
    let(:env) { {} }

    it 'reads model and candidates from a project config file' do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, '.commiti.yml')
        File.write(config_path, <<~YAML)
          model: gemini-2.5-flash
          candidates: 3
          no_copy: true
          auto_split: true
          diff_summary_workers: 6
          git:
            base_branch: develop
        YAML

        config = described_class.load(env: { 'COMMITI_CONFIG' => config_path }, cwd: dir)

        expect(config[:model]).to eq('gemini-2.5-flash')
        expect(config[:candidates]).to eq(3)
        expect(config[:no_copy]).to be(true)
        expect(config[:auto_split]).to be(true)
        expect(config[:diff_summary_workers]).to eq(6)
        expect(config[:base_branch]).to eq('develop')
      end
    end

    it 'env vars override YAML behavior flags' do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, '.commiti.yml')
        File.write(config_path, "model: gemini-2.5-flash\ncandidates: 3\n")

        config = described_class.load(
          env: { 'COMMITI_CONFIG' => config_path, 'COMMITI_MODEL' => 'gemma-4-31b-it', 'COMMITI_CANDIDATES' => '1' },
          cwd: dir
        )

        expect(config[:model]).to eq('gemma-4-31b-it')
        expect(config[:candidates]).to eq(1)
      end
    end

    it 'absent env vars do not overwrite YAML values' do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, '.commiti.yml')
        File.write(config_path, "model: gemini-2.5-flash\n")

        config = described_class.load(env: { 'COMMITI_CONFIG' => config_path }, cwd: dir)

        expect(config[:model]).to eq('gemini-2.5-flash')
      end
    end

    it 'global config provides defaults that project config overrides' do
      Dir.mktmpdir do |global_dir|
        Dir.mktmpdir do |project_dir|
          global_path = File.join(global_dir, '.commiti.yml')
          project_path = File.join(project_dir, '.commiti.yml')

          File.write(global_path, "model: gemini-2.5-flash\ncandidates: 2\n")
          File.write(project_path, "candidates: 5\n")

          allow(described_class).to receive(:global_config_path).and_return(global_path)

          config = described_class.load(env: { 'COMMITI_CONFIG' => project_path }, cwd: project_dir)

          expect(config[:model]).to eq('gemini-2.5-flash')
          expect(config[:candidates]).to eq(5)
        end
      end
    end

    it 'project text_generation overrides global without wiping other global text_generation keys' do
      Dir.mktmpdir do |global_dir|
        Dir.mktmpdir do |project_dir|
          global_path = File.join(global_dir, '.commiti.yml')
          project_path = File.join(project_dir, '.commiti.yml')

          File.write(global_path, <<~YAML)
            text_generation:
              commit:
                subject_case: lowercase
              pr:
                sections:
                  - name: Global Section
                    guidance: Global guidance.
          YAML
          File.write(project_path, <<~YAML)
            text_generation:
              commit:
                subject_case: uppercase
          YAML

          allow(described_class).to receive(:global_config_path).and_return(global_path)

          config = described_class.load(env: { 'COMMITI_CONFIG' => project_path }, cwd: project_dir)

          expect(config[:text_generation][:commit][:subject_case]).to eq('uppercase')
          expect(config[:text_generation][:pr][:sections].first[:name]).to eq('Global Section')
        end
      end
    end

    it 'does not read API key secrets from YAML' do
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, '.commiti.yml')
        File.write(config_path, "google_api_key: should-be-ignored\n")

        config = described_class.load(env: { 'COMMITI_CONFIG' => config_path }, cwd: dir)

        expect(config[:google_api_key]).to be_nil
      end
    end
  end

  describe '.deep_merge (private)' do
    it 'overrides scalar values from the override hash' do
      base = { model: 'gemma', candidates: 1 }
      override = { model: 'gemini-flash' }

      result = described_class.send(:deep_merge, base, override)

      expect(result[:model]).to eq('gemini-flash')
      expect(result[:candidates]).to eq(1)
    end

    it 'recursively merges nested hashes' do
      base = { text_generation: { commit: { subject_case: 'preserve' }, pr: { sections: [] } } }
      override = { text_generation: { commit: { subject_case: 'uppercase' } } }

      result = described_class.send(:deep_merge, base, override)

      expect(result[:text_generation][:commit][:subject_case]).to eq('uppercase')
      expect(result[:text_generation][:pr]).to eq({ sections: [] })
    end

    it 'replaces arrays entirely rather than appending' do
      base = { 'pr' => { 'sections' => %w[A B] } }
      override = { 'pr' => { 'sections' => ['C'] } }

      result = described_class.send(:deep_merge, base, override)

      expect(result['pr']['sections']).to eq(['C'])
    end
  end

  describe '.global_config_path (private)' do
    it 'returns the expanded path to ~/.commiti.yml' do
      expected = File.expand_path('~/.commiti.yml')

      expect(described_class.send(:global_config_path)).to eq(expected)
    end
  end
end
