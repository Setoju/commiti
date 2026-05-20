# frozen_string_literal: true

module Commiti
  module Clipboard
    def self.copy(text)
      case platform
      when :mac
        IO.popen('pbcopy', 'w') { |io| io.write(text) }
        :copied
      when :linux
        if command_exists?('xclip')
          IO.popen('xclip -selection clipboard', 'w') { |io| io.write(text) }
          :copied
        elsif command_exists?('xsel')
          IO.popen('xsel --clipboard --input', 'w') { |io| io.write(text) }
          :copied
        end
      when :windows
        IO.popen('clip', 'w') { |io| io.write(text) }
        :copied
      end
    end

    def self.platform
      if RUBY_PLATFORM.include?('darwin')
        :mac
      elsif RUBY_PLATFORM.include?('linux')
        :linux
      elsif RUBY_PLATFORM.include?('mingw') || RUBY_PLATFORM.include?('mswin')
        :windows
      else
        :unknown
      end
    end

    def self.command_exists?(cmd)
      system('which', cmd, out: File::NULL, err: File::NULL)
    end
  end
end
