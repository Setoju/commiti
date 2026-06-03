# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::ScopeInferrer do
  describe '.infer' do
    it 'matches common scopes from path segments' do
      scope = described_class.infer(
        files: ['app/services/auth/token_service.rb'],
        common_scopes: %w[auth api]
      )

      expect(scope).to eq('auth')
    end

    it 'falls back to built-in mappings when no common scope matches' do
      scope = described_class.infer(
        files: ['app/controllers/sessions_controller.rb'],
        common_scopes: []
      )

      expect(scope).to eq('api')
    end

    it 'returns nil when inferred scopes are mixed' do
      scope = described_class.infer(
        files: ['app/controllers/users_controller.rb', 'app/models/user.rb'],
        common_scopes: []
      )

      expect(scope).to be_nil
    end

    it 'infers scope from lib namespace when available' do
      scope = described_class.infer(
        files: ['lib/payments/processor.rb'],
        common_scopes: []
      )

      expect(scope).to eq('payments')
    end

    it 'applies FALLBACK_SCOPE_MAP to lib/* next segments' do
      scope = described_class.infer(
        files: ['lib/controllers/users_controller.rb'],
        common_scopes: []
      )

      expect(scope).to eq('api')
    end

    it 'returns nil when no files are provided' do
      scope = described_class.infer(files: [], common_scopes: %w[auth])

      expect(scope).to be_nil
    end
  end
end
