# frozen_string_literal: true

module Commiti
  module CommitExecution
    def self.maybe_commit(initial_message, run_stage:, print_message:)
      working_message = initial_message

      loop do
        action = Commiti::InteractivePrompt.ask_commit_action

        case action
        when :yes
          result, next_message = handle_yes_action(
            working_message,
            run_stage: run_stage,
            print_message: print_message
          )
          return result if result

          working_message = next_message
        when :edit
          edited = edit_message_until_valid(working_message)
          if edited.nil?
            puts "\n#{Commiti::TerminalUI.status(:fail, 'Editor did not exit successfully.')}\n\n"
            next
          end

          working_message = edited
          print_message.call(working_message)
        else
          print_skip_message
          return :skipped
        end
      end
    end

    def self.handle_yes_action(working_message, run_stage:, print_message:)
      errors = Commiti::InteractivePrompt.commit_message_errors(working_message)
      return commit_message(working_message, run_stage: run_stage) if errors.empty?

      puts "\n#{Commiti::TerminalUI.status(:warn, 'Current message needs fixes before commit:')}"
      errors.each { |error| puts "- #{error}" }

      unless Commiti::InteractivePrompt.ask_yes_no('Open editor to fix now?', default: :yes)
        print_skip_message
        return [:skipped, nil]
      end

      edited = edit_message_until_valid(working_message)
      if edited.nil?
        puts "\n#{Commiti::TerminalUI.status(:fail, 'Editor did not exit successfully. Commit skipped.')}\n\n"
        return [:skipped, nil]
      end

      print_message.call(edited)
      [nil, edited]
    end
    private_class_method :handle_yes_action

    def self.commit_message(message, run_stage:)
      output = run_stage.call('Writing commit') { Commiti::GitWriter.commit_with_message_file(message) }
      puts output unless output.to_s.strip.empty?
      puts "\n#{Commiti::TerminalUI.status(:success, 'Commit created.')}\n\n"
      [:committed, nil]
    end
    private_class_method :commit_message

    def self.print_skip_message
      puts "\n#{Commiti::TerminalUI.status(:warn, 'Commit skipped.')}\n\n"
    end
    private_class_method :print_skip_message

    def self.edit_message_until_valid(initial_message)
      working = initial_message

      loop do
        edited = Commiti::InteractivePrompt.edit_message(working)
        return nil if edited.nil?

        if edited == working.to_s.strip
          puts "\n#{Commiti::TerminalUI.status(:info, 'No changes detected in editor.')}"
          return edited unless Commiti::InteractivePrompt.ask_yes_no('Re-open editor now?', default: :yes)

          next
        end

        errors = Commiti::InteractivePrompt.commit_message_errors(edited)
        return edited if errors.empty?

        puts "\n#{Commiti::TerminalUI.status(:warn, 'Edited message needs fixes:')}"
        errors.each { |error| puts "- #{error}" }
        return edited unless Commiti::InteractivePrompt.ask_yes_no('Re-open editor now?', default: :yes)

        working = edited
      end
    end
    private_class_method :edit_message_until_valid
  end
end
