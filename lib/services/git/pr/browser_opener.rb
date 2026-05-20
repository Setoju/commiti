# frozen_string_literal: true

module Commiti
  module PrBrowserOpener
    def self.open_in_browser(url)
      success = if windows?
                  open_windows_browser(url)
                elsif mac?
                  system('open', url)
                else
                  system('xdg-open', url)
                end

      raise 'Failed to open browser for PR URL.' unless success

      nil
    end

    def self.open_windows_browser(url)
      cleaned_url = url.to_s.strip.sub(/\A\\+/, '')

      # Prefer shell protocol handler. This bypasses cmd/explorer parsing of '&'.
      return true if system('rundll32', 'url.dll,FileProtocolHandler', cleaned_url)

      # PowerShell fallback, passing URL as an argument to avoid command parsing.
      system(
        'powershell',
        '-NoProfile',
        '-Command',
        '$u=$args[0]; Start-Process -FilePath $u',
        '--',
        cleaned_url
      )
    end

    def self.windows?
      RUBY_PLATFORM.include?('mingw') || RUBY_PLATFORM.include?('mswin')
    end

    def self.mac?
      RUBY_PLATFORM.include?('darwin')
    end
  end
end
