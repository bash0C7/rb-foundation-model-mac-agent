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

  def test_parse_returns_nil_on_malformed_yaml
    text = "```tool_call\nname: fs.read\nargs: [unbalanced\n```\n"
    assert_nil(TC.parse(text))
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

  # --- parser tolerance (any-language fence) ---

  def test_parse_extracts_tool_call_from_ruby_flavored_fence
    # Apple FM commonly wraps tool_call in ```ruby instead of ```tool_call
    text = <<~TXT
      Sure, I will read the file.
      ```ruby
      name: fs.read
      args:
        path: ./sample.rb
      ```
    TXT
    call = RbFoundationModelMacAgent::ToolCall.parse(text)
    assert_not_nil(call, "should parse tool_call inside ```ruby fence")
    assert_equal("fs.read", call["name"])
    assert_equal("./sample.rb", call.dig("args", "path"))
  end

  def test_parse_extracts_tool_call_with_tool_call_banner_inside_fence
    # Apple FM sometimes inserts literal "tool_call" as the first line inside fence
    text = <<~TXT
      ```ruby
      tool_call
      name: fs.read
      args:
        path: ./sample.rb
      ```
    TXT
    call = RbFoundationModelMacAgent::ToolCall.parse(text)
    assert_not_nil(call, "should strip 'tool_call' banner and parse the rest")
    assert_equal("fs.read", call["name"])
  end

  def test_parse_ignores_plain_ruby_code_without_tool_call_structure
    text = <<~TXT
      Here is some Ruby:
      ```ruby
      puts "hello"
      x = 1 + 2
      ```
    TXT
    call = RbFoundationModelMacAgent::ToolCall.parse(text)
    assert_nil(call, "plain code without name:<ns>.<tool> must not be treated as tool_call")
  end

  def test_parse_ignores_yaml_without_valid_namespaced_name
    text = <<~TXT
      ```tool_call
      name: not_namespaced
      args: {}
      ```
    TXT
    call = RbFoundationModelMacAgent::ToolCall.parse(text)
    assert_nil(call, "name without <ns>.<tool> format must be rejected")
  end

  def test_parse_returns_nil_for_text_without_any_fence
    text = "Just a plain final answer about Ruby."
    call = RbFoundationModelMacAgent::ToolCall.parse(text)
    assert_nil(call)
  end

  def test_parse_still_accepts_canonical_tool_call_fence
    text = <<~TXT
      ```tool_call
      name: fs.read
      args:
        path: ./sample.rb
      ```
    TXT
    call = RbFoundationModelMacAgent::ToolCall.parse(text)
    assert_not_nil(call)
    assert_equal("fs.read", call["name"])
  end
end
