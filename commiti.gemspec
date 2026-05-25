# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'commiti'
  spec.version = '1.3.4'
  spec.authors = ['Setoju']
  spec.email = ['setoju48@gmail.com']
  spec.summary = 'AI-powered commit and PR description generator using Google AI models'
  spec.description = 'Generates git commit messages and PR descriptions using Google AI text generation models. '
  spec.homepage = 'https://github.com/setoju/commiti'
  spec.license = 'MIT'

  spec.files = Dir['lib/**/*', 'bin/*'] + ['LICENSE', 'README.md']
  spec.bindir = 'bin'
  spec.executables = ['commiti']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.2'

  spec.add_dependency 'dotenv', '~> 3.2'
  spec.add_dependency 'httparty', '~> 0.21'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
