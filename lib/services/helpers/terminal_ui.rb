# frozen_string_literal: true

require 'io/console'

module Commiti
  module TerminalUI
    COLORS = {
      green: 32,
      red: 31,
      yellow: 33,
      blue: 34,
      cyan: 36,
      magenta: 35,
      gray: 90,
      bold: 1
    }.freeze

    UNICODE_ICONS = {
      success: '✔',
      fail: '✖',
      info: 'ℹ',
      warn: '⚠'
    }.freeze

    ASCII_ICONS = {
      success: '+',
      fail: 'x',
      info: 'i',
      warn: '!'
    }.freeze

    UNICODE_MARKERS = {
      prompt: '›',
      header: '▸',
      bullet: '•',
      rule: '─'
    }.freeze

    ASCII_MARKERS = {
      prompt: '>',
      header: '>',
      bullet: '-',
      rule: '-'
    }.freeze

    def self.supports_ansi?
      return false unless $stdout.tty?
      return false if ENV.key?('NO_COLOR')

      term = ENV.fetch('TERM', '').downcase
      term != 'dumb'
    end

    def self.supports_unicode?
      encoding = $stdout.external_encoding || Encoding.default_external
      encoding.name.upcase.include?('UTF-8')
    rescue StandardError
      false
    end

    def self.width
      cols = IO.console&.winsize&.last
      cols = ENV.fetch('COLUMNS', nil) if cols.nil? || cols <= 0
      cols = cols.to_i
      cols = 80 if cols <= 0
      [cols, 120].min
    rescue StandardError
      80
    end

    def self.color(text, *styles)
      return text unless supports_ansi?

      codes = styles.filter_map { |style| COLORS[style] }
      return text if codes.empty?

      "\e[#{codes.join(';')}m#{text}\e[0m"
    end

    def self.status(kind, text)
      symbol = icon_for(kind)
      color_style = case kind
                    when :success then :green
                    when :fail then :red
                    when :warn then :yellow
                    else :blue
                    end
      "#{color(symbol, color_style, :bold)} #{text}"
    end

    def self.separator(length = nil)
      char = marker(:rule)
      color(char * (length || width), :gray)
    end

    def self.header(text)
      "#{color(marker(:header), :cyan, :bold)} #{color(text, :bold, :cyan)}"
    end

    def self.prompt(text)
      "#{color(marker(:prompt), :cyan, :bold)} #{text}"
    end

    def self.muted(text)
      color(text, :gray)
    end

    def self.panel(title, body)
      [
        separator,
        header(title),
        separator,
        body.to_s.rstrip,
        separator
      ].join("\n")
    end

    def self.bullet(text)
      "#{marker(:bullet)} #{text}"
    end

    def self.bullets(items)
      items.map { |item| bullet(item) }.join("\n")
    end

    def self.pad_right(text, length)
      padding = [length - visible_length(text), 0].max
      "#{text}#{' ' * padding}"
    end

    def self.visible_length(text)
      strip_ansi(text).length
    end

    def self.strip_ansi(text)
      text.to_s.gsub(/\e\[[0-9;]*m/, '')
    end

    def self.banner(title:, subtitle: nil, meta: nil)
      body_lines = [subtitle, meta].compact.join("\n")
      panel(title, body_lines)
    end

    def self.icon_for(kind)
      (supports_unicode? ? UNICODE_ICONS : ASCII_ICONS).fetch(kind, '*')
    end
    private_class_method :icon_for

    def self.marker(kind)
      (supports_unicode? ? UNICODE_MARKERS : ASCII_MARKERS).fetch(kind, '*')
    end
    private_class_method :marker
  end
end
