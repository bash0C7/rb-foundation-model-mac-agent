# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestSession < Test::Unit::TestCase
  S = RbFoundationModelMacAgent::Session

  def echo_agent(overrides = {})
    {
      name: "yamabiko", engine: "scripted", model: "default", fs_root: ".",
      allowed_mcp: [], allowed_builtin: [],
      max_iters: 4, body: "山彦",
      scripted_replies: ["{input}"],
    }.merge(overrides)
  end

  def test_turn_with_echo_engine_appends_user_and_assistant
    Dir.mktmpdir do |dir|
      reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: File.join(dir, "mcp.json"))
      begin
        sess = S.new(agent_def: echo_agent(fs_root: dir), mcp_registry: reg)
        display = FakeDisplay.new
        sess.turn("hello", display: display)
        assert_equal(["user", "assistant"], sess.messages.map { |m| m[:role] })
        assert_equal("hello", sess.messages.last[:content])
        assert_includes(display.appended.map(&:first), "hello")
      ensure
        reg.close_all
      end
    end
  end

  def test_react_loop_invokes_tool_then_continues
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.txt")
      File.write(path, "FILECONTENT")
      reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: File.join(dir, "mcp.json"))
      agent = echo_agent(
        engine: "apple-fm",       # routed via injected engine, not actually used
        fs_root: dir, allowed_builtin: ["fs.read"],
      )
      scripted = ScriptedEngine.new([
        "Let me read the file.\n```tool_call\nname: fs.read\nargs:\n  path: #{path}\n```",
        "The file contains FILECONTENT.",
      ])
      sess = S.new(agent_def: agent, mcp_registry: reg, engine: scripted)
      display = FakeDisplay.new
      sess.turn("what is in x.txt?", display: display)

      roles = sess.messages.map { |m| m[:role] }
      assert_equal(%w[user assistant user assistant], roles)
      assert_match(/tool_result/, sess.messages[2][:content])
      assert_match(/FILECONTENT/, sess.messages[2][:content])
      assert_equal(2, scripted.calls.size, "engine should be called once per ReAct iteration")
    end
  end

  def test_max_iters_terminates_and_reports
    Dir.mktmpdir do |dir|
      reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: File.join(dir, "mcp.json"))
      agent = echo_agent(fs_root: dir, max_iters: 2, allowed_builtin: ["fs.read"])
      forever = "```tool_call\nname: fs.read\nargs:\n  path: #{File.join(dir, "nope.txt")}\n```"
      scripted = ScriptedEngine.new([forever, forever, forever])
      sess = S.new(agent_def: agent, mcp_registry: reg, engine: scripted)
      display = FakeDisplay.new
      sess.turn("loop pls", display: display)
      assert_equal(2, scripted.calls.size)
      assert_true(display.dialogs.any? { |c, _| c.include?("max iterations") })
    end
  end

  def test_reset_clears_messages
    Dir.mktmpdir do |dir|
      reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: File.join(dir, "mcp.json"))
      sess = S.new(agent_def: echo_agent(fs_root: dir), mcp_registry: reg)
      sess.turn("hi", display: FakeDisplay.new)
      sess.reset
      assert_empty(sess.messages)
      reg.close_all
    end
  end

  def test_reset_also_resets_engine
    Dir.mktmpdir do |dir|
      reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: File.join(dir, "mcp.json"))
      scripted = ScriptedEngine.new(["ok"])
      sess = S.new(agent_def: echo_agent(fs_root: dir), mcp_registry: reg, engine: scripted)
      sess.turn("hi", display: FakeDisplay.new)
      sess.reset
      assert_empty(sess.messages)
      assert_equal(1, scripted.reset_count)
    end
  end

  def test_system_prompt_includes_tools_for_llm
    Dir.mktmpdir do |dir|
      reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: File.join(dir, "mcp.json"))
      agent = echo_agent(engine: "ollama", allowed_builtin: ["fs.read"], fs_root: dir)
      scripted = ScriptedEngine.new(["ok"])
      sess = S.new(agent_def: agent, mcp_registry: reg, engine: scripted)
      sess.turn("hi", display: FakeDisplay.new)
      assert_match(/Available tools/, sess.system_prompt)
      assert_match(/fs\.read/,        sess.system_prompt)
    end
  end

  def test_system_prompt_scripted_engine_skips_tools_section
    Dir.mktmpdir do |dir|
      reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: File.join(dir, "mcp.json"))
      sess = S.new(agent_def: echo_agent(fs_root: dir), mcp_registry: reg)
      assert_false(sess.system_prompt.include?("Available tools"))
    end
  end
end
