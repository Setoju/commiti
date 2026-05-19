# frozen_string_literal: true

module Commiti
  module TerminalUI
    COLORS = {
      green: 32,
      red: 31,
      yellow: 33,
      blue: 34,
      cyan: 36,
      gray: 90,
      bold: 1
    }.freeze

    SYMBOLS = {
      success: '✅',
      fail: '❌',
      info: 'ℹ',
      warn: '⚠'
    }.freeze

    def self.supports_ansi?
      return false unless $stdout.tty?
      return false if ENV.key?('NO_COLOR')

      term = ENV.fetch('TERM', '').downcase
      term != 'dumb'
    end

    def self.color(text, *styles)
      return text unless supports_ansi?

      codes = styles.filter_map { |style| COLORS[style] }
      return text if codes.empty?

      "\e[#{codes.join(';')}m#{text}\e[0m"
    end

    def self.status(kind, text)
      symbol = SYMBOLS.fetch(kind, '*')
      color_style = case kind
                    when :success then :green
                    when :fail then :red
                    when :warn then :yellow
                    else :blue
                    end
      "#{color(symbol, color_style)} #{text}"
    end

    def self.separator(length = 60)
      color('─' * length, :gray)
    end

    def self.header(text)
      color(text, :bold, :cyan)
    end
  end
end
