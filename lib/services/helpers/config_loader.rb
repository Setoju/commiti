# frozen_string_literal: true

require 'yaml'
require_relative '../text_generation_style'

module Commiti
  class ConfigLoader
    DEFAULT_TEXT_GENERATION_CONFIG = Commiti::TextGenerationStyle::DEFAULT_CONFIG

    DEFAULT_CONFIG = {
      google_api_key: nil,
      github_token: nil,
      gitlab_token: nil,
      gitbucket_token: nil,
      model: Commiti::GoogleClient::DEFAULT_MODEL,
      candidates: 1,
      base_branch: 'main',
      no_copy: false,
      auto_split: false,
      diff_summary_workers: 4,
      temperature: Commiti::GoogleClient::DEFAULT_TEMPERATURE,
      timeout_seconds: Commiti::GoogleClient::DEFAULT_TIMEOUT_SECONDS,
      open_timeout_seconds: Commiti::GoogleClient::DEFAULT_OPEN_TIMEOUT_SECONDS,
      text_generation: DEFAULT_TEXT_GENERATION_CONFIG
    }.freeze

    # Loads configuration from environment variables.
    # Keys are returned as symbols with parsed values.
    def self.load(env: ENV, cwd: Dir.pwd)
      global_raw = load_global_yaml
      project_raw = read_yaml_config(configured_path(env: env, cwd: cwd))
      merged_raw = deep_merge(global_raw, project_raw)

      DEFAULT_CONFIG
        .merge(yaml_behavior_config(merged_raw))
        .merge(
          google_api_key: google_api_key_from_env(env),
          github_token: present_or_nil(env.fetch('COMMITI_GITHUB_TOKEN', nil)),
          gitlab_token: present_or_nil(env.fetch('COMMITI_GITLAB_TOKEN', nil)),
          gitbucket_token: present_or_nil(env.fetch('COMMITI_GITBUCKET_TOKEN', nil)),
          text_generation: Commiti::TextGenerationStyle.normalize(merged_raw)
        )
        .merge(env_behavior_overrides(env))
    end

    def self.configured_path(env:, cwd:)
      configured = present_or_nil(env.fetch('COMMITI_CONFIG', nil))
      path = configured || File.join(cwd, '.commiti.yml')
      File.expand_path(path, cwd)
    end
    private_class_method :configured_path

    def self.read_yaml_config(path)
      return {} unless File.file?(path)

      raw = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
      raw.is_a?(Hash) ? raw : {}
    rescue StandardError
      {}
    end
    private_class_method :read_yaml_config

    def self.global_config_path
      File.expand_path('~/.commiti.yml')
    end
    private_class_method :global_config_path

    def self.load_global_yaml
      read_yaml_config(global_config_path)
    end
    private_class_method :load_global_yaml

    def self.deep_merge(base, override)
      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
    private_class_method :deep_merge

    def self.google_api_key_from_env(env)
      present_or_nil(env.fetch('GOOGLE_API_KEY', nil)) ||
        present_or_nil(env.fetch('GEMINI_API_KEY', nil)) ||
        present_or_nil(env.fetch('GOOGLE_GENERATIVE_AI_API_KEY', nil))
    end
    private_class_method :google_api_key_from_env

    def self.present_or_nil(value)
      normalized = value.to_s.strip
      normalized.empty? ? nil : normalized
    end
    private_class_method :present_or_nil

    def self.yaml_behavior_config(merged)
      git = lookup_key(merged, 'git') || {}
      {}.tap do |result|
        model = present_or_nil(lookup_key(merged, 'model').to_s)
        result[:model] = model if model

        candidates = safe_integer(lookup_key(merged, 'candidates'))
        result[:candidates] = candidates unless candidates.nil?

        base_branch = present_or_nil(lookup_key(git, 'base_branch').to_s)
        result[:base_branch] = base_branch if base_branch

        no_copy = as_boolean(lookup_key(merged, 'no_copy'))
        result[:no_copy] = no_copy unless no_copy.nil?

        auto_split = as_boolean(lookup_key(merged, 'auto_split'))
        result[:auto_split] = auto_split unless auto_split.nil?

        workers = safe_integer(lookup_key(merged, 'diff_summary_workers'))
        result[:diff_summary_workers] = workers unless workers.nil?
      end
    end
    private_class_method :yaml_behavior_config

    def self.env_behavior_overrides(env)
      {}.tap do |result|
        model = present_or_nil(env.fetch('COMMITI_MODEL', nil))
        result[:model] = model if model

        candidates = safe_integer(env.fetch('COMMITI_CANDIDATES', nil))
        result[:candidates] = candidates unless candidates.nil?

        base_branch = present_or_nil(env.fetch('COMMITI_BASE_BRANCH', nil))
        result[:base_branch] = base_branch if base_branch

        no_copy = safe_boolean_from_string(env.fetch('COMMITI_NO_COPY', nil))
        result[:no_copy] = no_copy unless no_copy.nil?

        auto_split = safe_boolean_from_string(env.fetch('COMMITI_AUTO_SPLIT', nil))
        result[:auto_split] = auto_split unless auto_split.nil?

        temperature = safe_float(env.fetch('COMMITI_MODEL_TEMPERATURE', nil))
        result[:temperature] = temperature unless temperature.nil?

        timeout = safe_integer(env.fetch('COMMITI_MODEL_TIMEOUT_SECONDS', nil))
        result[:timeout_seconds] = timeout unless timeout.nil?

        open_timeout = safe_integer(env.fetch('COMMITI_MODEL_OPEN_TIMEOUT_SECONDS', nil))
        result[:open_timeout_seconds] = open_timeout unless open_timeout.nil?

        workers = safe_integer(env.fetch('COMMITI_DIFF_SUMMARY_WORKERS', nil))
        result[:diff_summary_workers] = workers unless workers.nil?
      end
    end
    private_class_method :env_behavior_overrides

    def self.lookup_key(hash, key)
      return nil unless hash.is_a?(Hash)
      hash.key?(key) ? hash[key] : hash[key.to_sym]
    end
    private_class_method :lookup_key

    def self.as_boolean(value)
      return value if value == true || value == false
      nil
    end
    private_class_method :as_boolean

    def self.safe_integer(value)
      return nil if value.nil? || value.to_s.strip.empty?
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :safe_integer

    def self.safe_float(value)
      return nil if value.nil? || value.to_s.strip.empty?
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :safe_float

    def self.safe_boolean_from_string(value)
      return nil if value.nil? || value.to_s.strip.empty?
      normalized = value.to_s.strip.downcase
      return true if %w[1 true yes on].include?(normalized)
      return false if %w[0 false no off].include?(normalized)
      nil
    end
    private_class_method :safe_boolean_from_string
  end
end
