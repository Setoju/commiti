# frozen_string_literal: true

module Commiti
  module Spinner
    FRAMES = ['|', '/', '-', '\\'].freeze
    INTERVAL_SECONDS = 0.1

    def self.run(message)
      unless $stdout.tty?
        puts Commiti::TerminalUI.status(:info, "#{message}...")
        result = yield
        puts Commiti::TerminalUI.status(:success, message)
        return result
      end

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
        result = yield
      rescue StandardError => e
        error = e
      ensure
        done = true
        spinner_thread.join

        kind = error.nil? ? :success : :fail
        print "\r#{Commiti::TerminalUI.status(kind, message)}\n"
        $stdout.flush
      end

      raise error unless error.nil?

      result
    end
  end
end
