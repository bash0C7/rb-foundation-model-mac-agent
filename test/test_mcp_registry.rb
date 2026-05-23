# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require "fileutils"

class TestMcpRegistry < Test::Unit::TestCase
  STDIO_SERVER = File.expand_path(
    "../../../modelcontextprotocol/ruby-sdk/examples/stdio_server.rb",
    __dir__,
  )

  def setup
    @tmp = Dir.mktmpdir
    @config = File.join(@tmp, "mcp.json")
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def write_config(hash)
    File.write(@config, JSON.pretty_generate(hash))
  end

  def test_load_empty_when_file_missing
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    assert_equal([], reg.list)
  end

  def test_connects_stdio_server_and_lists_tools
    omit "ruby-sdk stdio_server.rb not found at #{STDIO_SERVER}" unless File.file?(STDIO_SERVER)
    write_config(
      servers: {
        demo: { kind: "stdio", cmd: "ruby", args: [STDIO_SERVER] },
      },
    )
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    begin
      tool_names = reg.tools("demo").map { |t| t[:name] }.sort
      assert_includes(tool_names, "echo")
      assert_includes(tool_names, "example_tool")
    ensure
      reg.close_all
    end
  end

  def test_call_invokes_tool_and_returns_text
    omit "ruby-sdk stdio_server.rb not found" unless File.file?(STDIO_SERVER)
    write_config(
      servers: {
        demo: { kind: "stdio", cmd: "ruby", args: [STDIO_SERVER] },
      },
    )
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    begin
      result = reg.call(server: "demo", tool: "echo", args: { "message" => "ping" })
      assert_match(/ping/, result)
    ensure
      reg.close_all
    end
  end

  def test_failed_server_keeps_registry_alive
    write_config(
      servers: { bad: { kind: "stdio", cmd: "/nonexistent/binary/path", args: [] } },
    )
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    info = reg.list.find { |i| i[:name] == "bad" }
    assert_equal(:error, info[:status])
    reg.close_all
  end

  def test_add_runtime_persists_to_config
    omit "ruby-sdk stdio_server.rb not found" unless File.file?(STDIO_SERVER)
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    reg.add("demo", kind: "stdio", cmd: "ruby", args: [STDIO_SERVER])
    begin
      saved = JSON.parse(File.read(@config))
      assert_equal("stdio",      saved.dig("servers", "demo", "kind"))
      assert_equal("ruby",       saved.dig("servers", "demo", "cmd"))
    ensure
      reg.close_all
    end
  end

  def test_failed_add_is_not_persisted
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    assert_raise(RuntimeError) do
      reg.add("bad", kind: "stdio", cmd: "/nonexistent", args: [])
    end
    assert_false(File.exist?(@config))
    reg.close_all
  end

  def test_remove_drops_from_config
    omit "ruby-sdk stdio_server.rb not found" unless File.file?(STDIO_SERVER)
    write_config(
      servers: { demo: { kind: "stdio", cmd: "ruby", args: [STDIO_SERVER] } },
    )
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    reg.remove("demo")
    saved = JSON.parse(File.read(@config))
    assert_equal({}, saved.fetch("servers"))
    reg.close_all
  end
end
