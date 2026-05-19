# frozen_string_literal: true

module Commiti
  module MessagePresenter
    def self.print_summarization_notice(summarized_result)
      if summarized_result[:fallback_reason]
        puts "\n#{Commiti::TerminalUI.status(:warn, summarized_result[:fallback_reason])}\n"
      elsif summarized_result[:summarized]
        puts "\n#{Commiti::TerminalUI.status(:info, 'Diff is large — summarizing first to preserve prompt focus.')}\n"
      end
    end

    def self.select_message(candidates)
      if candidates.length == 1
        print_message(candidates.first)
        return candidates.first
      end

      print_candidates(candidates)
      selected_index = Commiti::InteractivePrompt.ask_candidate_selection(candidates.length)
      selected_message = candidates[selected_index]
      puts "\n#{Commiti::TerminalUI.status(:info, "Using candidate #{selected_index + 1}.")}"
      print_message(selected_message)
      selected_message
    end

    def self.maybe_copy_to_clipboard(message, no_copy:, run_stage:)
      return if no_copy

      copied = run_stage.call('Copying output to clipboard') { Commiti::Clipboard.copy(message) }
      if copied
        puts "#{Commiti::TerminalUI.status(:success, 'Copied output to clipboard!')}\n\n"
      else
        puts "#{Commiti::TerminalUI.status(:warn, 'Clipboard unavailable. Install xclip: sudo apt install xclip')}\n\n"
      end
    end

    def self.print_message(message)
      puts "\n#{Commiti::TerminalUI.separator}"
      puts Commiti::TerminalUI.header('Generated output')
      puts Commiti::TerminalUI.separator
      puts message
      puts "#{Commiti::TerminalUI.separator}\n"
    end

    def self.print_candidates(candidates)
      candidates.each_with_index do |candidate, index|
        puts "\n#{Commiti::TerminalUI.header("Candidate #{index + 1}")}"
        print_message(candidate)
      end
    end
    private_class_method :print_candidates
  end
end
