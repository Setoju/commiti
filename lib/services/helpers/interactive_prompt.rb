# frozen_string_literal: true

require 'io/console'
require 'shellwords'
require 'tempfile'
require 'tty-reader'

module Commiti
  module InteractivePrompt
    COMMIT_SUBJECT_MAX_LENGTH = 100
    COMMIT_PREFIX = /\A(feat|fix|chore|refactor|docs|style|test|perf|ci|build|revert)(\([^)]+\))?!?:\s+\S/i

    def self.ask_yes_no(question, default: :no)
      suffix = default == :yes ? '[Y/n]' : '[y/N]'
      input = read_input("#{question} #{suffix} ")
      return default == :yes ? :yes : nil if input.nil?

      value = input.strip.downcase
      return :yes if %w[y yes].include?(value)
      return nil if %w[n no].include?(value)
      return default == :yes ? :yes : nil if value.empty?

      nil
    end

    def self.ask_commit_action
      input = read_input('Commit with this message? [y/e/N] ')
      return :no if input.nil?

      value = input.strip.downcase
      return :yes if %w[y yes].include?(value)
      return :edit if %w[e edit].include?(value)

      :no
    end

    def self.ask_candidate_selection(count, default: 1)
      return 0 if count <= 1

      loop do
        input = read_input("Select candidate [1-#{count}] (default: #{default}): ")
        return default - 1 if input.nil?

        value = input.strip
        return default - 1 if value.empty?
        return value.to_i - 1 if value.match?(/\A\d+\z/) && value.to_i.between?(1, count)

        puts "Please type a number between 1 and #{count}."
      end
    end

    def self.edit_message(initial_message)
      # Keep the temp file closed while the external editor runs.
      # On Windows, open handles can prevent editors like Notepad from
      # saving in place, which can make edits appear to be ignored.
      file = Tempfile.new(['commiti-msg', '.txt'])
      begin
        file.write("#{initial_message.to_s.rstrip}\n")
        file.flush
        file.close

        command = editor_command
        success = system(*command, file.path)
        return nil unless success

        File.read(file.path, mode: 'r:bom|utf-8').strip
      ensure
        file.unlink
      end
    end

    def self.commit_message_errors(message)
      cleaned = message.to_s.strip
      return ['Message cannot be empty.'] if cleaned.empty?

      first_line = cleaned.lines.first.to_s.strip
      errors = []
      errors << 'First line must start with a conventional commit type (feat:, fix:, etc.).' unless first_line.match?(COMMIT_PREFIX)
      errors << "First line should be #{COMMIT_SUBJECT_MAX_LENGTH} characters or fewer." if first_line.length > COMMIT_SUBJECT_MAX_LENGTH
      errors
    end

    def self.editor_command
      preferred = ENV.fetch('VISUAL', nil)
      preferred = ENV.fetch('EDITOR', nil) if preferred.to_s.strip.empty?

      if preferred.to_s.strip.empty?
        return ['notepad'] if windows?

        return ['vi']
      end

      command = Shellwords.split(preferred)
      command << '--wait' if code_editor_command?(command.first) && !command.include?('--wait')

      command
    end

    def self.code_editor_command?(exe)
      name = File.basename(exe.to_s).downcase
      ['code', 'code.cmd', 'code.exe', 'codium', 'codium.cmd', 'codium.exe'].include?(name)
    end

    def self.windows?
      RUBY_PLATFORM.include?('mingw') || RUBY_PLATFORM.include?('mswin')
    end

    def self.read_input(prompt)
      if io_console_available?
        reader.read_line(prompt)
      else
        print prompt
        $stdin.gets
      end
    rescue Interrupt
      nil
    end

    def self.reader
      @reader ||= TTY::Reader.new
    end

    def self.io_console_available?
      !IO.console.nil?
    rescue StandardError
      false
    end
  end
end
