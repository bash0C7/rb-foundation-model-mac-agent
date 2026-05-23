# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestToolCall < Test::Unit::TestCase
  TC = RbFoundationModelMacAgent::ToolCall

  def test_parse_picks_first_fenced_block
    text = <<~TXT
      thinking...
      ```tool_call
      name: fs.read
      args:
        path: /tmp/a.txt
      ```
      ```tool_call
      name: fs.read
      args:
        path: /tmp/b.txt
      ```
    TXT
    call = TC.parse(text)
    assert_equal("fs.read", call.fetch("name"))
    assert_equal("/tmp/a.txt", call.dig("args", "path"))
  end

  def test_parse_returns_nil_when_no_fence
    assert_nil(TC.parse("just a final reply, no fence here"))
  end

  def test_parse_raises_on_malformed_yaml
    text = "```tool_call\nname: fs.read\nargs: [unbalanced\n```\n"
    assert_raise(Psych::SyntaxError) { TC.parse(text) }
  end

  def test_dispatch_allowed_builtin
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.txt")
      File.write(path, "hi")
      agent_def = { allowed_builtin: ["fs.read"], allowed_mcp: [] }
      result = TC.dispatch(
        { "name" => "fs.read", "args" => { "path" => path } },
        agent_def: agent_def, fs_root: dir, mcp_registry: nil,
      )
      assert_equal(true, result[:ok])
      assert_equal("hi", result[:content])
    end
  end

  def test_dispatch_rejects_disallowed_builtin
    result = TC.dispatch(
      { "name" => "fs.write", "args" => { "path" => "/tmp/x", "content" => "" } },
      agent_def: { allowed_builtin: ["fs.read"], allowed_mcp: [] },
      fs_root: "/tmp", mcp_registry: nil,
    )
    assert_equal(false, result[:ok])
    assert_match(/not allowed/, result[:error])
  end

  def test_dispatch_routes_mcp_to_registry
    fake_registry = Object.new
    def fake_registry.call(server:, tool:, args:)
      "called server=#{server} tool=#{tool} args=#{args.inspect}"
    end
    agent_def = { allowed_builtin: [], allowed_mcp: ["chiebukuro"] }
    result = TC.dispatch(
      { "name" => "chiebukuro.search", "args" => { "q" => "ruby" } },
      agent_def: agent_def, fs_root: "/tmp", mcp_registry: fake_registry,
    )
    assert_equal(true, result[:ok])
    assert_equal('called server=chiebukuro tool=search args={"q" => "ruby"}', result[:content])
  end

  def test_dispatch_rejects_disallowed_mcp_server
    result = TC.dispatch(
      { "name" => "evil.do", "args" => {} },
      agent_def: { allowed_builtin: [], allowed_mcp: ["chiebukuro"] },
      fs_root: "/tmp", mcp_registry: nil,
    )
    assert_equal(false, result[:ok])
    assert_match(/mcp 'evil' not allowed/, result[:error])
  end
end
