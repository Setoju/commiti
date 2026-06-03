# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::FlowContextBuilder do
  it 'passes text generation styling into the prompt builder' do
    diff = <<~DIFF
      diff --git a/app/models/user.rb b/app/models/user.rb
      @@ -1 +1 @@
      -old
      +new
    DIFF
    style_config = {
      commit: { subject_case: 'lowercase' },
      pr: { sections: [{ name: 'Overview', guidance: 'Summarize the change.' }] }
    }

    allow(Commiti::DiffParser).to receive(:split_by_file_lines).and_return([
                                                                             { path: 'app/models/user.rb',
                                                                               lines: ['diff --git a/app/models/user.rb b/app/models/user.rb\n'] }
                                                                           ])
    allow(Commiti::DiffParser).to receive(:metadata_from_line_chunks).and_return({ files: ['app/models/user.rb'] })
    allow(Commiti::ChangeGrouping).to receive(:group).and_return([])
    allow(Commiti::DiffSummarizer).to receive(:summarize_if_needed).and_return({ summarized: false, content: diff })

    expect(Commiti::PromptBuilder).to receive(:build).with(
      type: :commit,
      diff: diff,
      summarized: false,
      raw_diff: diff,
      diff_metadata: { files: ['app/models/user.rb'] },
      style_config: style_config,
      style_profile: nil,
      inferred_scope: nil
    ).and_return({ system: 'system', user: 'user' })

    context = described_class.build(
      flow_type: :commit,
      diff: diff,
      client: instance_double('Commiti::GoogleClient'),
      run_stage: ->(_message, &block) { block.call },
      model: Commiti::GoogleClient::DEFAULT_MODEL,
      text_generation_config: style_config
    )

    expect(context[:prompt]).to eq({ system: 'system', user: 'user' })
  end

  describe 'scope inference (private)' do
    it 'matches common scopes from path segments' do
      result = described_class.send(:infer_scope_for_files,
        files: ['app/services/auth/token_service.rb'],
        common_scopes: %w[auth api]
      )
      expect(result).to eq('auth')
    end

    it 'falls back to built-in mappings when no common scope matches' do
      result = described_class.send(:infer_scope_for_files,
        files: ['app/controllers/sessions_controller.rb'],
        common_scopes: []
      )
      expect(result).to eq('api')
    end

    it 'returns nil when inferred scopes are mixed' do
      result = described_class.send(:infer_scope_for_files,
        files: ['app/controllers/users_controller.rb', 'app/models/user.rb'],
        common_scopes: []
      )
      expect(result).to be_nil
    end

    it 'infers scope from lib namespace when available' do
      result = described_class.send(:infer_scope_for_files,
        files: ['lib/payments/processor.rb'],
        common_scopes: []
      )
      expect(result).to eq('payments')
    end

    it 'applies FALLBACK_SCOPE_MAP to lib/* next segments' do
      result = described_class.send(:infer_scope_for_files,
        files: ['lib/controllers/users_controller.rb'],
        common_scopes: []
      )
      expect(result).to eq('api')
    end

    it 'returns nil when no files are provided' do
      result = described_class.send(:infer_scope_for_files,
        files: [],
        common_scopes: %w[auth]
      )
      expect(result).to be_nil
    end
  end
end
