# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::Spinner do
  describe '.run' do
    it 'runs synchronously without thread when stdout is not a tty' do
      allow($stdout).to receive(:tty?).and_return(false)

      result = nil
      expect do
        result = described_class.run('Working') { 42 }
      end.to output(/Working\.\.\..*✅ Working/m).to_stdout

      expect(result).to eq(42)
    end

    it 'prints fail state and re-raises errors in tty mode' do
      allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

      expect do
        expect do
          described_class.run('Boom') { raise 'failure' }
        end.to raise_error('failure')
      end.to output(/❌.*Boom/m).to_stdout
    end
  end
end
