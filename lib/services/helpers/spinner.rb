# frozen_string_literal: true

module Commiti
  module Spinner
    FRAMES = ['|', '/', '-', '\\'].freeze
    INTERVAL_SECONDS = 0.1

    def self.run(message, &block)
      return run_without_spinner(message, &block) unless $stdout.tty?

      done = false
      error = nil
      result = nil

      spinner_thread = Thread.new do
        index = 0
        until done
          frame = Commiti::TerminalUI.color(FRAMES[index % FRAMES.length], :cyan)
          print "\r#{frame} #{message}"
          $stdout.flush
          index += 1
          sleep INTERVAL_SECONDS
        end
      end

      begin
        result = block.call
      rescue StandardError => e
        error = e
      ensure
        done = true
        spinner_thread.join

        print "\r#{final_status_line(error, message)}\n"
        $stdout.flush
      end

      raise error unless error.nil?

      result
    end

    def self.run_without_spinner(message, &block)
      puts Commiti::TerminalUI.status(:info, "#{message}...")
      result = block.call
      puts Commiti::TerminalUI.status(:success, message)
      result
    end
    private_class_method :run_without_spinner

    def self.final_status_line(error, message)
      kind = error.nil? ? :success : :fail
      Commiti::TerminalUI.status(kind, message)
    end
    private_class_method :final_status_line
  end
end
