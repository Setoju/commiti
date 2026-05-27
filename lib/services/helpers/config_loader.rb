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
      temperature: Commiti::GoogleClient::DEFAULT_TEMPERATURE,
      timeout_seconds: Commiti::GoogleClient::DEFAULT_TIMEOUT_SECONDS,
      open_timeout_seconds: Commiti::GoogleClient::DEFAULT_OPEN_TIMEOUT_SECONDS,
      text_generation: DEFAULT_TEXT_GENERATION_CONFIG
    }.freeze

    # Loads configuration from environment variables.
    # Keys are returned as symbols with parsed values.
    def self.load(env: ENV, cwd: Dir.pwd)
      DEFAULT_CONFIG.merge(
        google_api_key: google_api_key_from_env(env),
        github_token: present_or_nil(env.fetch('COMMITI_GITHUB_TOKEN', nil)),
        gitlab_token: present_or_nil(env.fetch('COMMITI_GITLAB_TOKEN', nil)),
        gitbucket_token: present_or_nil(env.fetch('COMMITI_GITBUCKET_TOKEN', nil)),
        model: present_or_default(env.fetch('COMMITI_MODEL', nil), DEFAULT_CONFIG[:model]),
        candidates: integer_or_default(env.fetch('COMMITI_CANDIDATES', nil), DEFAULT_CONFIG[:candidates]),
        base_branch: present_or_default(env.fetch('COMMITI_BASE_BRANCH', nil), DEFAULT_CONFIG[:base_branch]),
        no_copy: boolean_or_default(env.fetch('COMMITI_NO_COPY', nil), DEFAULT_CONFIG[:no_copy]),
        auto_split: boolean_or_default(env.fetch('COMMITI_AUTO_SPLIT', nil), DEFAULT_CONFIG[:auto_split]),
        temperature: float_or_default(env.fetch('COMMITI_MODEL_TEMPERATURE', nil), DEFAULT_CONFIG[:temperature]),
        timeout_seconds: integer_or_default(env.fetch('COMMITI_MODEL_TIMEOUT_SECONDS', nil), DEFAULT_CONFIG[:timeout_seconds]),
        open_timeout_seconds: integer_or_default(env.fetch('COMMITI_MODEL_OPEN_TIMEOUT_SECONDS', nil),
                                                 DEFAULT_CONFIG[:open_timeout_seconds]),
        text_generation: load_text_generation_config(env: env, cwd: cwd)
      )
    end

    def self.load_text_generation_config(env:, cwd:)
      config_path = configured_path(env: env, cwd: cwd)
      project_config = read_yaml_config(config_path)
      Commiti::TextGenerationStyle.normalize(project_config)
    end
    private_class_method :load_text_generation_config

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

    def self.present_or_default(value, fallback)
      present_or_nil(value) || fallback
    end
    private_class_method :present_or_default

    def self.integer_or_default(value, fallback)
      return fallback if value.nil? || value.to_s.strip.empty?

      Integer(value)
    rescue ArgumentError
      fallback
    end
    private_class_method :integer_or_default

    def self.float_or_default(value, fallback)
      return fallback if value.nil? || value.to_s.strip.empty?

      Float(value)
    rescue ArgumentError
      fallback
    end
    private_class_method :float_or_default

    def self.boolean_or_default(value, fallback)
      return fallback if value.nil? || value.to_s.strip.empty?

      normalized = value.to_s.strip.downcase
      return true if %w[1 true yes on].include?(normalized)
      return false if %w[0 false no off].include?(normalized)

      fallback
    end
    private_class_method :boolean_or_default
  end
end
