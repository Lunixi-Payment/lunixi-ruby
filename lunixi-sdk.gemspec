# frozen_string_literal: true

require_relative 'lib/lunixi/version'

Gem::Specification.new do |spec|
  spec.name = 'lunixi-sdk'
  spec.version = Lunixi::VERSION
  spec.authors = ['Lunixi']
  spec.email = ['developer@lunixi.com']
  spec.summary = 'Server-side Ruby client for Lunixi payments and signed webhooks'
  spec.description = 'Ed25519 request signing, synchronized token caching, payment and fraud clients, safe retries, and raw-body v2 webhook verification.'
  spec.homepage = 'https://github.com/Lunixi-Payment/lunixi-ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'
  spec.files = Dir['lib/**/*.rb', 'docs/**/*.md', '.github/assets/*', 'README.md', 'README.tr.md', 'MIGRATION-1.0.md', 'LICENSE', 'CHANGELOG.md', 'SECURITY.md']
  spec.require_paths = ['lib']
  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'documentation_uri' => "#{spec.homepage}#readme",
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }
  spec.add_dependency 'base64', '>= 0.2', '< 1'
  spec.add_dependency 'json', '>= 2.9', '< 3'
  spec.add_dependency 'net-http', '>= 0.6', '< 1'
  spec.add_dependency 'openssl', '>= 3.3', '< 5'
end
