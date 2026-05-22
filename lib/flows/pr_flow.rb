# frozen_string_literal: true

module Commiti
  module Flows
    class PrFlow < BaseFlow
      private

      def flow_type
        :pr
      end

      def collect_diff
        run_stage("Collecting diff against #{options[:base_branch]}...HEAD") do
          Commiti::GitReader.branch_diff(base_branch: options[:base_branch])
        end
      end

      def finalize(message)
        maybe_open_pr_page(message, options[:base_branch])
      end

      def maybe_open_pr_page(description, base_branch)
        head_branch = Commiti::GitWriter.current_branch
        origin_url = Commiti::GitWriter.origin_url
        title = Commiti::PrOpener.suggest_title(description, head_branch: head_branch)

        prompt_text = 'Create PR and open it in browser now?'

        unless Commiti::InteractivePrompt.ask_yes_no(prompt_text, default: :no)
          puts "\nPR creation skipped.\n\n"
          return
        end

        api_result = run_stage('Creating PR/MR via provider API (if token configured)') do
          Commiti::PrCreator.create(
            origin_url: origin_url,
            base_branch: base_branch,
            head_branch: head_branch,
            title: title,
            body: description,
            config: options
          )
        end

        pr_url = api_result[:url]

        if pr_url.nil?
          case api_result[:reason]
          when :missing_token
            puts "\n#{Commiti::TerminalUI.status(:info, "No #{api_result[:provider]} token configured; using browser prefill fallback.")}"
          when :unsupported_provider
            puts "\n#{Commiti::TerminalUI.status(:warn, 'Provider API is unsupported; using browser prefill fallback.')}"
          when :api_error
            puts "\n#{Commiti::TerminalUI.status(:warn, "PR API create failed: #{api_result[:error]}. Using browser prefill fallback.")}"
          end

          pr_url = run_stage('Preparing prefilled PR URL') do
            Commiti::PrOpener.compare_url(
              origin_url: origin_url,
              base_branch: base_branch,
              head_branch: head_branch,
              title: title,
              body: description
            )
          end
        end

        run_stage('Opening browser') { Commiti::PrOpener.open_in_browser(pr_url) }
        puts "\nOpened PR page:\n#{pr_url}\n\n"
      end
    end
  end
end
