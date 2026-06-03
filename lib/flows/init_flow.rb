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

        yaml_written = if File.exist?(config_path)
                         answer = Commiti::InteractivePrompt.ask_yes_no("#{config_path} already exists. Update it?", default: :yes)
                         answer == :yes && write_yaml(config_path, provider[:key], provider[:default_model])
                       else
                         write_yaml(config_path, provider[:key], provider[:default_model])
                         true
                       end

        if yaml_written
          if global
            write_to_shell_profile(provider[:env_var], credential)
          else
            write_to_dotenv(provider[:env_var], credential)
            handle_gitignore
          end
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
            File.open(env_path, 'a') do |f|
              f.write("\n") unless content.end_with?("\n")
              f.puts(line)
            end
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
        File.open(profile, 'a') { |f| f.puts("\nexport #{env_var}=\"#{value}\"") }
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
