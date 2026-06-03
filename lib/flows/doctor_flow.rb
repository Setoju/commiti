# frozen_string_literal: true

require 'yaml'

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
        client.generate(system: 'Reply with: ok', user: 'ok', model: nil)
        ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        [:success, "provider responded (#{ms}ms)"]
      rescue Commiti::ConfigError => e
        [:fail, e.message]
      rescue StandardError => e
        [:fail, "could not reach provider: #{e.message}"]
      end

      def check_model
        model    = raw_config_model
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

      def raw_config_model
        project = File.join(Dir.pwd, '.commiti.yml')
        global  = File.expand_path('~/.commiti.yml')
        [project, global].each do |path|
          next unless File.file?(path)

          raw = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
          model = raw.is_a?(Hash) ? (raw['model'] || raw[:model]) : nil
          return model.to_s.strip if model && !model.to_s.strip.empty?
        end
        nil
      rescue StandardError
        nil
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
