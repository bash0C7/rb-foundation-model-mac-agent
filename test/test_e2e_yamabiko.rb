# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class TestE2eYamabiko < Test::Unit::TestCase
  def test_yamabiko_echoes_input_through_full_stack
    Dir.mktmpdir do |project_dir|
      gem_agents = File.expand_path("../agents", __dir__)
      assert_true(File.file?(File.join(gem_agents, "yamabiko.md")),
                  "yamabiko.md must be shipped with the gem")

      agent_def = RbFoundationModelMacAgent::AgentDef.load(
        "yamabiko", gem_agents_dir: gem_agents,
                    project_agents_dir: File.join(project_dir, "agents"),
      )
      registry = RbFoundationModelMacAgent::McpRegistry.new(
        config_path: File.join(project_dir, "mcp.json"),
      )
      begin
        session = RbFoundationModelMacAgent::Session.new(
          agent_def: agent_def, mcp_registry: registry,
        )
        display = FakeDisplay.new
        session.turn("hello yamabiko", display: display)
        assert_equal(%w[user assistant], session.messages.map { |m| m[:role] })
        assert_equal("hello yamabiko", session.messages.last[:content])
        assert_includes(display.appended.map(&:first), "hello yamabiko")
      ensure
        session&.close
        registry.close_all
      end
    end
  end
end
