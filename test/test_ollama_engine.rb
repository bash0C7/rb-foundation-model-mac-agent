# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "webmock/test_unit"

class TestOllamaEngine < Test::Unit::TestCase
  def setup
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  def test_stream_parses_ndjson_chunks
    body = [
      { message: { role: "assistant", content: "Hello " }, done: false }.to_json,
      { message: { role: "assistant", content: "world" }, done: false }.to_json,
      { message: { role: "assistant", content: "" }, done: true }.to_json,
    ].join("\n") + "\n"

    stub_request(:post, "http://localhost:11434/api/chat").to_return(
      status: 200, body: body, headers: { "Content-Type" => "application/x-ndjson" },
    )

    engine = RbFoundationModelMacAgent::OllamaEngine.new(
      model: "qwen3:8b", system_prompt: "you are a helper",
    )
    received = +""
    engine.stream([{ role: "user", content: "hi" }]) { |chunk| received << chunk }
    assert_equal("Hello world", received)
  end

  def test_stream_sends_system_then_messages
    captured_body = nil
    stub_request(:post, "http://localhost:11434/api/chat").with { |req| captured_body = req.body; true }
      .to_return(status: 200,
                 body: { message: { role: "assistant", content: "ok" }, done: true }.to_json + "\n")
    engine = RbFoundationModelMacAgent::OllamaEngine.new(
      model: "qwen3:8b", system_prompt: "SYS",
    )
    engine.stream([{ role: "user", content: "U1" }, { role: "assistant", content: "A1" }, { role: "user", content: "U2" }]) { |_| }
    payload = JSON.parse(captured_body)
    assert_equal("qwen3:8b", payload["model"])
    assert_equal(true,        payload["stream"])
    assert_equal(
      [["system", "SYS"], ["user", "U1"], ["assistant", "A1"], ["user", "U2"]],
      payload["messages"].map { |m| [m["role"], m["content"]] },
    )
  end

  def test_close_is_noop
    assert_nothing_raised do
      RbFoundationModelMacAgent::OllamaEngine.new(model: "x", system_prompt: "").close
    end
  end
end
