# frozen_string_literal: true

module Commiti
  module CommitExecution
    def self.maybe_commit(initial_message, run_stage:, print_message:)
      working_message = initial_message

      loop do
        action = Commiti::InteractivePrompt.ask_commit_action

        case action
        when :yes
          errors = Commiti::InteractivePrompt.commit_message_errors(working_message)
          unless errors.empty?
            puts "\nCurrent message needs fixes before commit:"
            errors.each { |error| puts "- #{error}" }

            if Commiti::InteractivePrompt.ask_yes_no('Open editor to fix now?', default: :yes)
              edited = edit_message_until_valid(working_message)
              if edited.nil?
                puts "\nEditor did not exit successfully. Commit skipped.\n\n"
                return :skipped
              end

              working_message = edited
              print_message.call(working_message)
              next
            end

            puts "\nCommit skipped.\n\n"
            return :skipped
          end

          output = run_stage.call('Writing commit') { Commiti::GitWriter.commit_with_message_file(working_message) }
          puts output unless output.to_s.strip.empty?
          puts "\nCommit created.\n\n"
          return :committed
        when :edit
          edited = edit_message_until_valid(working_message)
          if edited.nil?
            puts "\nEditor did not exit successfully.\n\n"
            next
          end

          working_message = edited
          print_message.call(working_message)
        else
          puts "\nCommit skipped.\n\n"
          return :skipped
        end
      end
    end

    def self.edit_message_until_valid(initial_message)
      working = initial_message

      loop do
        edited = Commiti::InteractivePrompt.edit_message(working)
        return nil if edited.nil?

        if edited == working.to_s.strip
          puts "\nNo changes detected in editor."
          return edited unless Commiti::InteractivePrompt.ask_yes_no('Re-open editor now?', default: :yes)

          next
        end

        errors = Commiti::InteractivePrompt.commit_message_errors(edited)
        return edited if errors.empty?

        puts "\nEdited message needs fixes:"
        errors.each { |error| puts "- #{error}" }
        return edited unless Commiti::InteractivePrompt.ask_yes_no('Re-open editor now?', default: :yes)

        working = edited
      end
    end
    private_class_method :edit_message_until_valid
  end
end
