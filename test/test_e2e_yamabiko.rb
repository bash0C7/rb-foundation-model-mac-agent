# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class TestE2eYamabiko < Test::Unit::TestCase
  def test_yamabiko_runs_loop_demo_through_full_stack
    Dir.mktmpdir do |project_dir|
      gem_agents = File.expand_path("../agents", __dir__)
      assert_true(File.file?(File.join(gem_agents, "yamabiko.md")),
                  "yamabiko.md must be shipped with the gem")

      File.write(File.join(project_dir, "sample.rb"), "class Greeter; end\n")

      agent_def = RbFoundationModelMacAgent::AgentDef.load(
        "yamabiko", gem_agents_dir: gem_agents,
                    project_agents_dir: File.join(project_dir, "agents"),
      ).merge(fs_root: project_dir)
      registry = RbFoundationModelMacAgent::McpRegistry.new(
        config_path: File.join(project_dir, "mcp.json"),
      )
      begin
        session = RbFoundationModelMacAgent::Session.new(
          agent_def: agent_def, mcp_registry: registry,
        )
        display = FakeDisplay.new
        session.turn("please demo loop", display: display)

        roles = session.messages.map { |m| m[:role] }
        assert_equal(%w[user assistant user assistant], roles,
                     "ReAct loop should produce 4 messages")
        assert_match(/tool_result/, session.messages[2][:content])
        assert_match(/class Greeter/, session.messages[2][:content])
        assert_match(/Greeter/, session.messages.last[:content])
      ensure
        session&.close
        registry.close_all
      end
    end
  end
end
