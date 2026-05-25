# frozen_string_literal: true

module Commiti
  module GroupEditor
    HELP_TEXT = <<~TEXT.freeze
      Select files by number, then choose where to move them.

      Examples:
        1,3,5     (select files 1, 3, 5)
        2-4       (select files 2 through 4)

      Targets:
        1..N move to an existing group
        n    new group
        a    auto-reassign (best matching group or new)
        c    cancel
    TEXT

    def self.edit(groups)
      return groups if groups.empty?
      return groups unless Commiti::InteractivePrompt.ask_yes_no('Edit auto-split groups before committing?', default: :no)

      working = deep_copy(groups)
      chunk_map = build_chunk_map(working)
      all_paths = working.flat_map { |group| group[:files] }.uniq
      path_order = all_paths.each_with_index.to_h

      puts "\n#{Commiti::TerminalUI.panel('Group editor', HELP_TEXT)}\n"

      loop do
        index_map, indexed_groups = index_groups(working)
        print_groups(indexed_groups, total: working.length)

        input = Commiti::InteractivePrompt.ask_text('Move which files? (numbers, Enter to finish)')
        break if input.nil? || input.empty?

        selected_indices = parse_indices(input, max_index: index_map.length)
        if selected_indices.empty?
          puts Commiti::TerminalUI.status(:warn, 'No valid file numbers selected.')
          next
        end

        selected_paths = selected_indices.map { |index| index_map[index] }.compact
        target = Commiti::InteractivePrompt.ask_text(
          "Move to group [1-#{working.length}], n=new, a=auto, c=cancel"
        ).to_s.strip.downcase

        next if target.empty? || target == 'c'

        case target
        when 'a'
          auto_reassign(working, selected_paths, chunk_map)
        when 'n'
          move_to_new_group(working, selected_paths, chunk_map)
        else
          group_index = integer_or_nil(target)
          unless group_index && working[group_index - 1]
            puts Commiti::TerminalUI.status(:warn, "Group #{target} does not exist.")
            next
          end

          move_to_group(working, group_index, selected_paths)
        end

        normalize_groups(working, chunk_map, path_order)
      end

      normalize_groups(working, chunk_map, path_order)
    end

    def self.print_groups(indexed_groups, total:)
      panels = indexed_groups.map do |group|
        title = "Group #{group[:index]}/#{total}"
        body = if group[:entries].empty?
                 Commiti::TerminalUI.muted('No files')
               else
                 group[:entries].map { |entry| "#{entry[:index]}. #{entry[:path]}" }.join("\n")
               end
        Commiti::TerminalUI.panel(title, body)
      end
      puts "\n#{panels.join("\n\n")}\n"
    end
    private_class_method :print_groups

    def self.index_groups(groups)
      index_map = {}
      indexed_groups = []
      counter = 1

      groups.each_with_index do |group, index|
        entries = group[:files].map do |path|
          entry = { index: counter, path: path }
          index_map[counter] = path
          counter += 1
          entry
        end
        indexed_groups << { index: index + 1, entries: entries }
      end

      [index_map, indexed_groups]
    end
    private_class_method :index_groups

    def self.parse_indices(text, max_index:)
      raw = text.to_s.strip
      return [] if raw.empty?

      indices = []
      invalid_tokens = []

      raw.split(/[,\s]+/).each do |token|
        next if token.empty?

        if token.match?(/\A\d+-\d+\z/)
          start_value, end_value = token.split('-').map(&:to_i)
          range = start_value <= end_value ? (start_value..end_value) : (end_value..start_value)
          indices.concat(range.to_a)
        elsif token.match?(/\A\d+\z/)
          indices << token.to_i
        else
          invalid_tokens << token
        end
      end

      invalid_tokens.each do |token|
        puts Commiti::TerminalUI.status(:warn, "Invalid token: #{token}")
      end

      indices = indices.uniq
      valid = indices.select { |value| value.between?(1, max_index) }
      (indices - valid).each do |value|
        puts Commiti::TerminalUI.status(:warn, "File number #{value} is out of range.")
      end
      valid
    end
    private_class_method :parse_indices

    def self.move_to_group(groups, group_index, paths)
      target = groups[group_index - 1]
      paths.each do |path|
        remove_path_from_groups(groups, path)
        target[:files] << path unless target[:files].include?(path)
      end
    end
    private_class_method :move_to_group

    def self.move_to_new_group(groups, paths, chunk_map)
      paths.each { |path| remove_path_from_groups(groups, path) }
      new_groups = build_groups_for_paths(paths, chunk_map)
      groups.concat(new_groups)
    end
    private_class_method :move_to_new_group

    def self.auto_reassign(groups, paths, chunk_map)
      origin_groups = find_origin_groups(groups, paths)
      paths.each { |path| remove_path_from_groups(groups, path) }

      remaining = []
      paths.each do |path|
        excluded = origin_groups[path] ? [origin_groups[path]] : []
        target = best_matching_group(path, groups, excluded_groups: excluded)
        if target
          target[:files] << path unless target[:files].include?(path)
        else
          remaining << path
        end
      end

      groups.concat(build_groups_for_paths(remaining, chunk_map)) if remaining.any?
    end
    private_class_method :auto_reassign

    def self.find_origin_groups(groups, paths)
      origin = {}
      groups.each do |group|
        group[:files].each do |path|
          origin[path] = group if paths.include?(path)
        end
      end
      origin
    end
    private_class_method :find_origin_groups

    def self.remove_path_from_groups(groups, path)
      groups.each { |group| group[:files].delete(path) }
    end
    private_class_method :remove_path_from_groups

    def self.best_matching_group(path, groups, excluded_groups:)
      candidates = groups - excluded_groups
      best = nil
      best_score = 0

      candidates.each do |group|
        score = group[:files].count { |existing| Commiti::ChangeGrouping.related?(path, existing) }
        next if score <= best_score

        best_score = score
        best = group
      end

      best_score.positive? ? best : nil
    end
    private_class_method :best_matching_group

    def self.build_groups_for_paths(paths, chunk_map)
      line_chunks = paths.map { |path| chunk_map[path] }.compact
      return [] if line_chunks.empty?

      Commiti::ChangeGrouping.group(line_chunks).map do |group|
        {
          id: group[:id],
          files: group[:files],
          chunks: group[:chunks]
        }
      end
    end
    private_class_method :build_groups_for_paths

    def self.build_chunk_map(groups)
      groups.flat_map { |group| group[:chunks] }
            .each_with_object({}) { |chunk, acc| acc[chunk[:path]] = chunk }
    end
    private_class_method :build_chunk_map

    def self.normalize_groups(groups, chunk_map, path_order)
      groups.reject! { |group| group[:files].empty? }
      groups.each do |group|
        group[:files] = group[:files].uniq.sort_by { |path| path_order[path] || path_order.length }
        group[:chunks] = group[:files].filter_map { |path| chunk_map[path] }
      end
      groups.each_with_index { |group, index| group[:id] = index + 1 }
    end
    private_class_method :normalize_groups

    def self.integer_or_nil(value)
      return nil unless value.to_s.match?(/\A\d+\z/)

      value.to_i
    end
    private_class_method :integer_or_nil

    def self.deep_copy(groups)
      groups.map do |group|
        {
          id: group[:id],
          files: group[:files].dup,
          chunks: group[:chunks].map(&:dup)
        }
      end
    end
    private_class_method :deep_copy
  end
end
