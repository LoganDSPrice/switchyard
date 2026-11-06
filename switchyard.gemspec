# frozen_string_literal: true

require_relative "lib/switchyard/version"

Gem::Specification.new do |spec|
  spec.name = "switchyard"
  spec.version = Switchyard::VERSION
  spec.authors = ["Logan Price"]
  spec.email = ["logandsprice@gmail.com"]

  spec.summary = "Modern environment and database parity CLI for Rails applications on Railway"
  spec.description = "Switchyard provides environment parity commands (console, logs, migrate, restore) for Rails on modern PaaS providers like Railway."
  spec.homepage = "https://github.com/LoganDSPrice/switchyard"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "bin/*", "README.md", "LICENSE*"]
  spec.bindir = "bin"
  spec.executables = ["switchyard", "dev", "staging", "production", "pr"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
end
