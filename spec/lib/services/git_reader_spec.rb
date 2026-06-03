# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::GitReader do
  describe '.branch_diff' do
    it 'rejects invalid branch names before running git' do
      expect do
        described_class.branch_diff(base_branch: 'main; rm -rf /')
      end.to raise_error('Invalid branch name.')
    end
  end

  describe '.commits_in_range' do
    it 'rejects invalid ranges before running git' do
      expect do
        described_class.commits_in_range(range: 'main; rm -rf /')
      end.to raise_error('Invalid changelog range.')
    end

    it 'parses commit log entries' do
      log_output = [
        "aaaaaaaa#{Commiti::GitReader::LOG_FIELD_SEPARATOR}feat: add widget#{Commiti::GitReader::LOG_FIELD_SEPARATOR}body",
        Commiti::GitReader::LOG_RECORD_SEPARATOR,
        "bbbbbbbb#{Commiti::GitReader::LOG_FIELD_SEPARATOR}fix: patch#{Commiti::GitReader::LOG_FIELD_SEPARATOR}",
        Commiti::GitReader::LOG_RECORD_SEPARATOR
      ].join

      allow(Open3).to receive(:capture3).and_return([log_output, '', instance_double(Process::Status, success?: true)])

      commits = described_class.commits_in_range(range: 'v1.2.0..HEAD')

      expect(commits.length).to eq(2)
      expect(commits[0][:sha]).to eq('aaaaaaaa')
      expect(commits[0][:subject]).to eq('feat: add widget')
      expect(commits[1][:sha]).to eq('bbbbbbbb')
      expect(commits[1][:subject]).to eq('fix: patch')
    end
  end
end
