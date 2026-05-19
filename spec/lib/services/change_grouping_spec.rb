# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Commiti::ChangeGrouping do
  describe '.group' do
    it 'groups related lib and spec files by logical stem' do
      chunks = [
        { path: 'lib/services/message_generator.rb', lines: [] },
        { path: 'spec/lib/services/message_generator_spec.rb', lines: [] },
        { path: 'README.md', lines: [] }
      ]

      groups = described_class.group(chunks)

      expect(groups.length).to eq(2)
      expect(groups[0][:files]).to eq([
                                        'lib/services/message_generator.rb',
                                        'spec/lib/services/message_generator_spec.rb'
                                      ])
      expect(groups[1][:files]).to eq(['README.md'])
    end

    it 'groups files sharing a meaningful namespace' do
      chunks = [
        { path: 'lib/services/git/git_writer.rb', lines: [] },
        { path: 'lib/services/git/diff_parser.rb', lines: [] },
        { path: 'lib/services/helpers/spinner.rb', lines: [] }
      ]

      groups = described_class.group(chunks)

      expect(groups.length).to eq(2)
      expect(groups[0][:files]).to eq([
                                        'lib/services/git/git_writer.rb',
                                        'lib/services/git/diff_parser.rb'
                                      ])
      expect(groups[1][:files]).to eq(['lib/services/helpers/spinner.rb'])
    end

    it 'returns empty when no paths are present' do
      expect(described_class.group([{ path: '', lines: [] }])).to eq([])
    end
  end
end
