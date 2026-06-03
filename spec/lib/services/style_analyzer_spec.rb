# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'open3'
require 'fileutils'

RSpec.describe Commiti::StyleAnalyzer do
  def git!(dir, *args)
    out, err, status = Open3.capture3('git', *args, chdir: dir)
    raise "git #{args.join(' ')} failed: #{err.strip.empty? ? out.strip : err.strip}" unless status.success?

    out
  end

  def with_temp_repo(prefix)
    dir = Dir.mktmpdir(prefix)
    yield dir
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  def commit!(dir, message, body: nil, file: 'history.txt')
    path = File.join(dir, file)
    File.write(path, '') unless File.exist?(path)
    File.open(path, 'a') { |handle| handle.puts(message) }
    git!(dir, 'add', file)
    if body
      git!(dir, 'commit', '-m', message, '-m', body)
    else
      git!(dir, 'commit', '-m', message)
    end
  end

  it 'analyzes conventional commit history for style cues' do
    with_temp_repo('commiti-style') do |dir|
      git!(dir, 'init')
      git!(dir, 'config', 'user.email', 'commiti-test@example.com')
      git!(dir, 'config', 'user.name', 'Commiti Test')

      commit!(dir, 'feat(api): add token rotation', body: 'Add rotation logic.')
      commit!(dir, 'feat(auth): add login')
      commit!(dir, 'fix(api): handle error')
      commit!(dir, 'refactor(auth): extract session store', body: 'Move store behind service.')
      commit!(dir, 'docs: update readme')
      commit!(dir, 'update config')

      Dir.chdir(dir) do
        profile = described_class.analyze(lookback: 20)

        expect(profile).to be_a(described_class::StyleProfile)
        expect(profile.dominant_types).to eq(%w[feat docs fix refactor])
        expect(profile.scope_usage_rate).to eq(0.8)
        expect(profile.common_scopes).to eq(%w[api auth])
        expect(profile.median_subject_length).to eq(13)
        expect(profile.uses_body).to be(true)
        expect(profile.subject_case).to eq('lowercase')
      end
    end
  end

  it 'returns nil when fewer than 5 conventional commits are found' do
    with_temp_repo('commiti-style-small') do |dir|
      git!(dir, 'init')
      git!(dir, 'config', 'user.email', 'commiti-test@example.com')
      git!(dir, 'config', 'user.name', 'Commiti Test')

      commit!(dir, 'feat(api): add token rotation')
      commit!(dir, 'fix(api): handle error')
      commit!(dir, 'docs: update readme')

      Dir.chdir(dir) do
        expect(described_class.analyze(lookback: 10)).to be_nil
      end
    end
  end
end
