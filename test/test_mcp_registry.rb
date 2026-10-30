# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require "fileutils"
require "rbconfig"

class TestMcpRegistry < Test::Unit::TestCase
  STDIO_SERVER = File.expand_path("fixtures/mcp_stdio_server.rb", __dir__)
  BAD_HANDSHAKE = File.expand_path("fixtures/mcp_bad_handshake.rb", __dir__)
  RUBY = RbConfig.ruby

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

  def demo_config
    { servers: { demo: { kind: "stdio", cmd: RUBY, args: [STDIO_SERVER] } } }
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def test_load_empty_when_file_missing
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    assert_equal([], reg.list)
  end

  def test_connects_stdio_server_and_lists_tools
    write_config(demo_config)
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    begin
      assert_equal(%w[echo fail], reg.tools("demo").map { |t| t[:name] }.sort)
      assert_equal(:ok, reg.list.first[:status])
    ensure
      reg.close_all
    end
  end

  def test_call_invokes_tool_and_returns_text
    write_config(demo_config)
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    begin
      assert_equal("echo: ping", reg.call(server: "demo", tool: "echo", args: { "message" => "ping" }))
    ensure
      reg.close_all
    end
  end

  def test_call_raises_when_tool_reports_error
    write_config(demo_config)
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    begin
      assert_raise_message(/demo\.fail failed: boom/) do
        reg.call(server: "demo", tool: "fail", args: {})
      end
    ensure
      reg.close_all
    end
  end

  def test_failed_server_keeps_registry_alive
    write_config(servers: { bad: { kind: "stdio", cmd: "/nonexistent/binary/path", args: [] } })
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    info = reg.list.find { |i| i[:name] == "bad" }
    assert_equal(:error, info[:status])
    assert_match(/Failed to spawn/, info[:error])
    reg.close_all
  end

  def test_failed_handshake_terminates_spawned_process
    pid_file = File.join(@tmp, "pid")
    write_config(servers: { bad: { kind: "stdio", cmd: RUBY, args: [BAD_HANDSHAKE, pid_file] } })
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    pid = Integer(File.read(pid_file))
    begin
      assert_equal(:error, reg.list.first[:status])
      assert_false(alive?(pid), "server process #{pid} must not outlive a failed handshake")
    ensure
      Process.kill("KILL", pid) if alive?(pid)
    end
  end

  def test_http_server_connect_failure_is_recorded
    write_config(servers: { web: { kind: "http", source: "http://127.0.0.1:1/mcp" } })
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    assert_equal(:error, reg.list.first[:status])
  end

  def test_add_runtime_persists_to_config
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    reg.add("demo", kind: "stdio", cmd: RUBY, args: [STDIO_SERVER])
    begin
      saved = JSON.parse(File.read(@config))
      assert_equal({ "kind" => "stdio", "cmd" => RUBY, "args" => [STDIO_SERVER] }, saved.dig("servers", "demo"))
    ensure
      reg.close_all
    end
  end

  def test_add_with_existing_name_replaces_and_disconnects_old_server
    write_config(demo_config)
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    old_transport = reg.instance_variable_get(:@entries).fetch("demo")[:client].transport
    begin
      reg.add("demo", kind: "stdio", cmd: RUBY, args: [STDIO_SERVER])
      assert_false(old_transport.connected?, "replaced server must be disconnected")
      assert_equal("echo: hi", reg.call(server: "demo", tool: "echo", args: { "message" => "hi" }))
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
    write_config(demo_config)
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    reg.remove("demo")
    saved = JSON.parse(File.read(@config))
    assert_equal({}, saved.fetch("servers"))
    reg.close_all
  end

  def test_remove_unknown_server_raises
    reg = RbFoundationModelMacAgent::McpRegistry.new(config_path: @config)
    assert_raise_message(/unknown MCP server: ghost/) { reg.remove("ghost") }
    assert_false(File.exist?(@config))
  end
end
