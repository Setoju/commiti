# frozen_string_literal: true

module Commiti
  module ChangeGrouping
    NOISE_DIRECTORIES = %w[lib spec test app src docs].freeze

    def self.group(line_chunks)
      paths = line_chunks.map { |chunk| chunk[:path].to_s.strip }.reject(&:empty?).uniq
      return [] if paths.empty?

      components = connected_components(paths)
      components.map.with_index(1) do |component, index|
        {
          id: index,
          files: component,
          chunks: line_chunks.select { |chunk| component.include?(chunk[:path]) }
        }
      end
    end

    def self.connected_components(paths)
      visited = {}
      ordered_components = []

      paths.each do |root|
        next if visited[root]

        stack = [root]
        visited[root] = true
        component = []

        until stack.empty?
          current = stack.pop
          component << current

          paths.each do |candidate|
            next if visited[candidate]
            next unless connected?(current, candidate)

            visited[candidate] = true
            stack << candidate
          end
        end

        ordered_components << component.sort_by { |path| paths.index(path) }
      end

      ordered_components
    end
    private_class_method :connected_components

    def self.connected?(left, right)
      return true if primary_namespace(left) == primary_namespace(right)
      return true if logical_stem(left) == logical_stem(right)

      left_segments = normalized_segments(left)
      right_segments = normalized_segments(right)
      shared_depth = [left_segments.length, right_segments.length].min

      (0...shared_depth).count { |index| left_segments[index] == right_segments[index] } >= 2
    end
    private_class_method :connected?

    def self.primary_namespace(path)
      segments = normalized_segments(path)
      return nil if segments.empty?

      segments.first(2).join('/')
    end
    private_class_method :primary_namespace

    def self.logical_stem(path)
      normalized = path.to_s
      normalized = normalized.sub(%r{\A(?:lib|spec|test|app|src)/}, '') while normalized.match?(%r{\A(?:lib|spec|test|app|src)/})
      normalized = normalized.sub(/_spec\.[^.]+\z/, '')
      normalized = normalized.sub(/\.[^.]+\z/, '')
      normalized
    end
    private_class_method :logical_stem

    def self.normalized_segments(path)
      path.to_s.split('/').reject { |segment| segment.empty? || NOISE_DIRECTORIES.include?(segment) }
    end
    private_class_method :normalized_segments
  end
end
