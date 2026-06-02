# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Commiti::Flows::DoctorFlow do
  let(:tmpdir) { Dir.mktmpdir }
  let(:flow)   { described_class.new }

  after  { FileUtils.rm_rf(tmpdir) }
  before { allow(Dir).to receive(:pwd).and_return(tmpdir) }

  describe '#run' do
    before do
      allow(flow).to receive(:check_reachability).and_return([:success, 'provider responded (42ms)'])
      allow(flow).to receive(:check_git_remote).and_return([:success, 'origin → git@github.com:u/r.git'])
    end

    context 'all checks pass' do
      before do
        Dir.mkdir(File.join(tmpdir, '.git'))
        File.write(File.join(tmpdir, '.commiti.yml'), "provider: ollama\nmodel: llama3.2\n")
      end

      it 'exits 0' do
        expect { flow.run }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end

      it 'prints a line for each check' do
        expect do
          begin
            flow.run
          rescue SystemExit
            nil
          end
        end.to output(/git repo/i).to_stdout
      end
    end

    context 'a check fails' do
      it 'exits 1' do
        allow(flow).to receive(:check_reachability).and_return([:fail, 'unreachable'])
        expect { flow.run }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end
    end
  end

  describe '#check_git_repo (private)' do
    it 'returns :success when .git exists' do
      Dir.mkdir(File.join(tmpdir, '.git'))
      level, = flow.send(:check_git_repo)
      expect(level).to eq(:success)
    end

    it 'returns :fail when .git is absent' do
      level, = flow.send(:check_git_repo)
      expect(level).to eq(:fail)
    end
  end

  describe '#check_config_file (private)' do
    it 'returns :success with provider when project config exists' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: openai\n")
      level, msg = flow.send(:check_config_file)
      expect(level).to eq(:success)
      expect(msg).to include('openai')
    end

    it 'returns :warn when no config file found' do
      level, = flow.send(:check_config_file)
      expect(level).to eq(:warn)
    end
  end

  describe '#check_api_key (private)' do
    it 'returns :success when OPENAI_API_KEY is set' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: openai\n")
      stub_const('ENV', ENV.to_h.merge('OPENAI_API_KEY' => 'sk-key'))
      level, = flow.send(:check_api_key)
      expect(level).to eq(:success)
    end

    it 'returns :fail when OPENAI_API_KEY is missing' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: openai\n")
      stub_const('ENV', ENV.to_h.reject { |k, _| k == 'OPENAI_API_KEY' })
      level, msg = flow.send(:check_api_key)
      expect(level).to eq(:fail)
      expect(msg).to include('OPENAI_API_KEY')
    end

    it 'returns :success for ollama (no key needed)' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: ollama\n")
      level, = flow.send(:check_api_key)
      expect(level).to eq(:success)
    end
  end

  describe '#check_model (private)' do
    it 'returns :warn when no model is set' do
      level, = flow.send(:check_model)
      expect(level).to eq(:warn)
    end

    it 'returns :success for a valid google model name' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: google\nmodel: gemini-2.5-flash\n")
      level, = flow.send(:check_model)
      expect(level).to eq(:success)
    end

    it 'returns :warn for a suspicious model name' do
      File.write(File.join(tmpdir, '.commiti.yml'), "provider: google\nmodel: gpt-4o\n")
      level, = flow.send(:check_model)
      expect(level).to eq(:warn)
    end
  end

  describe '#check_git_remote (private)' do
    it 'returns :success when a remote URL is found' do
      allow(Commiti::GitReader).to receive(:remote_url).and_return('git@github.com:u/r.git')
      level, = flow.send(:check_git_remote)
      expect(level).to eq(:success)
    end

    it 'returns :warn when no remote is configured' do
      allow(Commiti::GitReader).to receive(:remote_url).and_return(nil)
      level, = flow.send(:check_git_remote)
      expect(level).to eq(:warn)
    end
  end
end
