# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'open3'
require 'fileutils'

class FakeGoogleClient
  def initialize
    @counter = 0
  end

  def generate(**_kwargs)
    @counter += 1
    "feat: grouped commit #{@counter}"
  end
end

RSpec.describe 'CommitFlow auto-split', :integration do
  def git!(dir, *args)
    out, err, status = Open3.capture3('git', *args, chdir: dir)
    raise "git #{args.join(' ')} failed: #{err.strip.empty? ? out.strip : err.strip}" unless status.success?

    out
  end

  it 'creates multiple commits with grouped files for connected changes' do
    Dir.mktmpdir('commiti-auto-split') do |dir|
      git!(dir, 'init')
      git!(dir, 'config', 'user.email', 'commiti-test@example.com')
      git!(dir, 'config', 'user.name', 'Commiti Test')

      FileUtils.mkdir_p(File.join(dir, 'lib/services'))
      FileUtils.mkdir_p(File.join(dir, 'spec/lib/services'))

      File.write(File.join(dir, 'lib/services/message_generator.rb'), "module M\nend\n")
      File.write(File.join(dir, 'spec/lib/services/message_generator_spec.rb'), "RSpec.describe M do\nend\n")
      File.write(File.join(dir, 'README.md'), "# Commiti\n")

      git!(dir, 'add', '-A')

      allow(Commiti::Spinner).to receive(:run) { |_message, &block| block.call }
      allow(Commiti::GoogleClient).to receive(:new).and_return(FakeGoogleClient.new)
      allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(false)
      allow(Commiti::InteractivePrompt).to receive(:ask_commit_action).and_return(:yes)

      Dir.chdir(dir) do
        flow = Commiti::Flows::CommitFlow.new(options: { auto_split: true, no_copy: true, candidates: 1 })
        flow.run
      end

      commit_count = git!(dir, 'rev-list', '--count', 'HEAD').strip.to_i
      expect(commit_count).to eq(2)

      hashes = git!(dir, 'rev-list', '--reverse', 'HEAD').lines.map(&:strip)

      changed_files_by_commit = hashes.map do |sha|
        git!(dir, 'show', '--name-only', '--pretty=format:', sha)
          .lines
          .map(&:strip)
          .reject(&:empty?)
          .sort
      end

      expect(changed_files_by_commit).to match_array([
                                                       ['README.md'],
                                                       ['lib/services/message_generator.rb', 'spec/lib/services/message_generator_spec.rb']
                                                     ])
    end
  end

  it 'restages remaining files when the second auto-split commit is skipped' do
    Dir.mktmpdir('commiti-auto-split-skip') do |dir|
      git!(dir, 'init')
      git!(dir, 'config', 'user.email', 'commiti-test@example.com')
      git!(dir, 'config', 'user.name', 'Commiti Test')

      FileUtils.mkdir_p(File.join(dir, 'lib/services'))
      FileUtils.mkdir_p(File.join(dir, 'spec/lib/services'))

      File.write(File.join(dir, 'lib/services/message_generator.rb'), "module M\nend\n")
      File.write(File.join(dir, 'spec/lib/services/message_generator_spec.rb'), "RSpec.describe M do\nend\n")
      File.write(File.join(dir, 'README.md'), "# Commiti\n")

      git!(dir, 'add', '-A')

      allow(Commiti::Spinner).to receive(:run) { |_message, &block| block.call }
      allow(Commiti::GoogleClient).to receive(:new).and_return(FakeGoogleClient.new)
      allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(false)
      allow(Commiti::InteractivePrompt).to receive(:ask_commit_action).and_return(:yes, :no)

      Dir.chdir(dir) do
        flow = Commiti::Flows::CommitFlow.new(options: { auto_split: true, no_copy: true, candidates: 1 })
        flow.run
      end

      commit_count = git!(dir, 'rev-list', '--count', 'HEAD').strip.to_i
      expect(commit_count).to eq(1)

      staged_files = git!(dir, 'diff', '--cached', '--name-only').lines.map(&:strip).reject(&:empty?).sort
      expect(staged_files).to eq(['lib/services/message_generator.rb', 'spec/lib/services/message_generator_spec.rb'])
    end
  end

  it 'groups nested namespace files into one commit' do
    Dir.mktmpdir('commiti-auto-split-nested') do |dir|
      git!(dir, 'init')
      git!(dir, 'config', 'user.email', 'commiti-test@example.com')
      git!(dir, 'config', 'user.name', 'Commiti Test')

      FileUtils.mkdir_p(File.join(dir, 'lib/services/git/commit'))
      FileUtils.mkdir_p(File.join(dir, 'spec/lib/services/git/commit'))

      File.write(File.join(dir, 'lib/services/git/commit/change_grouping.rb'), "module X\nend\n")
      File.write(File.join(dir, 'spec/lib/services/git/commit/change_grouping_spec.rb'), "RSpec.describe X do\nend\n")
      File.write(File.join(dir, '.env.example'), "KEY=value\n")

      git!(dir, 'add', '-A')

      allow(Commiti::Spinner).to receive(:run) { |_message, &block| block.call }
      allow(Commiti::GoogleClient).to receive(:new).and_return(FakeGoogleClient.new)
      allow(Commiti::InteractivePrompt).to receive(:ask_yes_no).and_return(false)
      allow(Commiti::InteractivePrompt).to receive(:ask_commit_action).and_return(:yes, :yes)

      Dir.chdir(dir) do
        flow = Commiti::Flows::CommitFlow.new(options: { auto_split: true, no_copy: true, candidates: 1 })
        flow.run
      end

      commit_count = git!(dir, 'rev-list', '--count', 'HEAD').strip.to_i
      expect(commit_count).to eq(2)

      hashes = git!(dir, 'rev-list', '--reverse', 'HEAD').lines.map(&:strip)
      changed_files_by_commit = hashes.map do |sha|
        git!(dir, 'show', '--name-only', '--pretty=format:', sha)
          .lines
          .map(&:strip)
          .reject(&:empty?)
          .sort
      end

      expect(changed_files_by_commit).to match_array([
                                                       ['.env.example'],
                                                       ['lib/services/git/commit/change_grouping.rb',
                                                        'spec/lib/services/git/commit/change_grouping_spec.rb']
                                                     ])
    end
  end
end
