# frozen_string_literal: true

require_relative 'git/git_reader'

module Commiti
  class StyleAnalyzer
    StyleProfile = Struct.new(
      :dominant_types,
      :scope_usage_rate,
      :common_scopes,
      :median_subject_length,
      :uses_body,
      :subject_case,
      keyword_init: true
    )

    MIN_SAMPLE_SIZE = 5

    def self.analyze(lookback: 50)
      commits = Commiti::GitReader.recent_commit_messages(n: lookback)
      samples = commits.filter_map { |commit| extract_sample(commit) }
      return nil if samples.length < MIN_SAMPLE_SIZE

      types = tally(samples.map { |sample| sample[:type] })
      scopes = tally(samples.map { |sample| sample[:scope] }.compact)
      subject_lengths = samples.map { |sample| sample[:subject].length }
      body_usage_rate = samples.count { |sample| sample[:has_body] }.to_f / samples.length

      StyleProfile.new(
        dominant_types: sort_by_frequency(types),
        scope_usage_rate: samples.count { |sample| sample[:scope] }.to_f / samples.length,
        common_scopes: sort_by_frequency(scopes),
        median_subject_length: median(subject_lengths),
        uses_body: body_usage_rate > 0.3,
        subject_case: majority_case(samples.map { |sample| sample[:subject_case] })
      )
    rescue StandardError
      nil
    end

    def self.profile_from_snapshot(snapshot)
      return snapshot if snapshot.is_a?(StyleProfile)
      return nil unless snapshot.is_a?(Hash)

      dominant_types = normalize_string_array(snapshot_value(snapshot, :dominant_types))
      common_scopes = normalize_string_array(snapshot_value(snapshot, :common_scopes))
      scope_usage_rate = normalize_rate(snapshot_value(snapshot, :scope_usage_rate))
      median_subject_length = normalize_integer(snapshot_value(snapshot, :median_subject_length))
      uses_body = snapshot_value(snapshot, :uses_body)
      subject_case = normalize_subject_case(snapshot_value(snapshot, :subject_case))

      return nil if dominant_types.empty?
      return nil if scope_usage_rate.nil? || median_subject_length.nil?
      return nil unless [true, false].include?(uses_body)
      return nil if subject_case.nil?

      StyleProfile.new(
        dominant_types: dominant_types,
        scope_usage_rate: scope_usage_rate,
        common_scopes: common_scopes,
        median_subject_length: median_subject_length,
        uses_body: uses_body,
        subject_case: subject_case
      )
    rescue StandardError
      nil
    end

    def self.extract_sample(commit)
      subject = commit[:subject].to_s.strip
      match = subject.match(Commiti::MessageGenerator::COMMIT_PREFIX_PATTERN)
      return nil unless match

      type = match[1].to_s.downcase
      scope = match[2].to_s
      scope = scope[1..-2] if scope.start_with?('(') && scope.end_with?(')')
      scope = nil if scope.to_s.strip.empty?

      subject_text = subject.sub(Commiti::MessageGenerator::COMMIT_PREFIX_PATTERN, '').strip
      {
        type: type,
        scope: scope&.downcase,
        subject: subject_text,
        has_body: !commit[:body].to_s.strip.empty?,
        subject_case: classify_subject_case(subject_text)
      }
    end
    private_class_method :extract_sample

    def self.classify_subject_case(subject)
      letter = subject.to_s.match(/[[:alpha:]]/)
      return nil unless letter

      char = letter[0]
      if char == char.upcase && char != char.downcase
        'uppercase'
      elsif char == char.downcase && char != char.upcase
        'lowercase'
      end
    end
    private_class_method :classify_subject_case

    def self.majority_case(cases)
      counts = tally(cases.compact)
      return 'mixed' if counts.empty?

      upper = counts.fetch('uppercase', 0)
      lower = counts.fetch('lowercase', 0)
      return 'mixed' if upper == lower

      upper > lower ? 'uppercase' : 'lowercase'
    end
    private_class_method :majority_case

    def self.tally(values)
      values.tally
    end
    private_class_method :tally

    def self.sort_by_frequency(counts)
      counts.sort_by { |key, count| [-count, key.to_s] }.map(&:first)
    end
    private_class_method :sort_by_frequency

    def self.median(values)
      sorted = values.compact.sort
      return 0 if sorted.empty?

      mid = sorted.length / 2
      return sorted[mid] if sorted.length.odd?

      ((sorted[mid - 1] + sorted[mid]) / 2.0).round
    end
    private_class_method :median

    def self.snapshot_value(snapshot, key)
      return snapshot[key] if snapshot.key?(key)

      key_string = key.to_s
      return snapshot[key_string] if snapshot.key?(key_string)

      key_symbol = key.to_sym
      return snapshot[key_symbol] if snapshot.key?(key_symbol)

      nil
    end
    private_class_method :snapshot_value

    def self.normalize_string_array(value)
      Array(value).map { |item| item.to_s.strip.downcase }.reject(&:empty?)
    end
    private_class_method :normalize_string_array

    def self.normalize_rate(value)
      return nil if value.nil?

      rate = Float(value)
      return nil if rate.negative? || rate > 1.0

      rate
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :normalize_rate

    def self.normalize_integer(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :normalize_integer

    def self.normalize_subject_case(value)
      normalized = value.to_s.strip.downcase
      %w[lowercase uppercase mixed].include?(normalized) ? normalized : nil
    end
    private_class_method :normalize_subject_case
  end
end
