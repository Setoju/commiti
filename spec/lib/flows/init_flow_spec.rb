# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'yaml'
require 'fileutils'

RSpec.describe Commiti::Flows::InitFlow do
  let(:tmpdir) { Dir.mktmpdir }
  let(:flow)   { described_class.new }

  after { FileUtils.rm_rf(tmpdir) }

  def stub_prompts(provider_name:, credential:, scope_name:, update_existing: :yes, add_gitignore: :yes)
    allow(Commiti::InteractivePrompt).to receive(:ask_select)
      .with(/provider/i, anything).and_return(provider_name)
    allow(Commiti::InteractivePrompt).to receive(:ask_text)
      .and_return(credential)
    allow(Commiti::InteractivePrompt).to receive(:ask_select)
      .with(/config/i, anything).and_return(scope_name)
    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no)
      .with(/Update/i, anything).and_return(update_existing)
    allow(Commiti::InteractivePrompt).to receive(:ask_yes_no)
      .with(/.gitignore/i, anything).and_return(add_gitignore)
  end

  context 'project config with OpenAI' do
    before do
      Dir.mkdir(File.join(tmpdir, '.git'))
      allow(Dir).to receive(:pwd).and_return(tmpdir)
      stub_prompts(provider_name: 'OpenAI', credential: 'sk-test', scope_name: 'Project (.commiti.yml)')
    end

    it 'writes provider and model to .commiti.yml' do
      flow.run
      config = YAML.safe_load_file(File.join(tmpdir, '.commiti.yml'))
      expect(config['provider']).to eq('openai')
      expect(config['model']).to eq('gpt-4o')
    end

    it 'writes OPENAI_API_KEY to .env' do
      flow.run
      expect(File.read(File.join(tmpdir, '.env'))).to include('OPENAI_API_KEY=sk-test')
    end

    it 'adds .env to .gitignore' do
      flow.run
      expect(File.read(File.join(tmpdir, '.gitignore'))).to include('.env')
    end

    it 'skips .gitignore update when .env is already listed' do
      File.write(File.join(tmpdir, '.gitignore'), ".env\n")
      expect(Commiti::InteractivePrompt).not_to receive(:ask_yes_no).with(/.gitignore/i, anything)
      flow.run
    end

    it 'does not write .env to .gitignore when user declines' do
      stub_prompts(provider_name: 'OpenAI', credential: 'sk-key',
                   scope_name: 'Project (.commiti.yml)', add_gitignore: nil)
      flow.run
      gitignore = File.join(tmpdir, '.gitignore')
      expect(File.exist?(gitignore) ? File.read(gitignore) : '').not_to include('.env')
    end
  end

  context 'global config with Google AI' do
    let(:global_config_path) { File.join(tmpdir, 'global_commiti.yml') }
    let(:shell_profile_path) { File.join(tmpdir, '.zshrc') }

    before do
      FileUtils.touch(shell_profile_path)
      allow(Dir).to receive(:pwd).and_return(tmpdir)
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with('~/.commiti.yml').and_return(global_config_path)
      allow(File).to receive(:expand_path).with('~/.zshrc').and_return(shell_profile_path)
      stub_prompts(provider_name: 'Google AI', credential: 'my-key', scope_name: 'Global (~/.commiti.yml)')
    end

    it 'writes provider and model to global config' do
      flow.run
      config = YAML.safe_load_file(global_config_path)
      expect(config['provider']).to eq('google')
    end

    it 'appends export KEY=value to shell profile' do
      flow.run
      expect(File.read(shell_profile_path)).to include('export GOOGLE_API_KEY="my-key"')
    end

    it 'does not create .env for global config' do
      flow.run
      expect(File.exist?(File.join(tmpdir, '.env'))).to be(false)
    end
  end

  context 'non-git directory' do
    before do
      allow(Dir).to receive(:pwd).and_return(tmpdir)
      stub_prompts(provider_name: 'OpenAI', credential: 'sk-key', scope_name: 'Project (.commiti.yml)')
    end

    it 'continues without raising' do
      expect { flow.run }.not_to raise_error
    end
  end

  context 'Ctrl-C on provider selection' do
    before { allow(Commiti::InteractivePrompt).to receive(:ask_select).and_return(nil) }

    it 'exits with status 0' do
      expect { flow.run }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end
end
