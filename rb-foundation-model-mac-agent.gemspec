# frozen_string_literal: true

require_relative "lib/rb_foundation_model_mac_agent/version"

Gem::Specification.new do |spec|
  spec.name          = "rb-foundation-model-mac-agent"
  spec.version       = RbFoundationModelMacAgent::VERSION
  spec.authors       = ["bash0C7"]
  spec.summary       = "Local-only coding agent CLI for macOS, backed by Apple Foundation Models or Ollama"
  spec.description   = "REPL-style local coding agent. Uses Apple Intelligence (rb-foundation-model-mac) " \
                       "or Ollama for the LLM, MCP servers for tool extensions, and a built-in fs read/write tool."
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files = Dir["lib/**/*.rb", "agents/*.md", "exe/*", "acceptance/**/*.rb", "README.md", "LICENSE"]
  spec.bindir        = "exe"
  spec.executables   = ["rb-foundation-model-mac-agent"]
  spec.require_paths = ["lib"]

  spec.add_dependency "baslash"
  spec.add_dependency "rb-foundation-model-mac"
  spec.add_dependency "rb-natural-language-mac"
  spec.add_dependency "rb-translation-mac"
  spec.add_dependency "mcp", "~> 0.17"
  # base64 is a transitive runtime dep of mcp (oauth/flow.rb requires "base64")
  # which is no longer bundled in Ruby 4.x. Pinning here until upstream declares it.
  # See: https://github.com/modelcontextprotocol/ruby-sdk
  spec.add_dependency "base64"

  spec.add_development_dependency "test-unit", "~> 3.6"
  spec.add_development_dependency "webmock",   "~> 3.0"
  spec.add_development_dependency "rake",      "~> 13.0"
end
