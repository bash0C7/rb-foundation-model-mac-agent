# frozen_string_literal: true

require_relative "test_helper"

class TestScriptedEngine < Test::Unit::TestCase
  E = RbFoundationModelMacAgent::ScriptedEngine

  def test_yields_single_reply
    engine = E.new(replies: ["hello"])
    out = nil
    engine.stream([{ role: "user", content: "anything" }]) { |chunk| out = chunk }
    assert_equal("hello", out)
  end

  def test_input_placeholder_substituted
    engine = E.new(replies: ["echo: {input}"])
    out = nil
    engine.stream([{ role: "user", content: "ping" }]) { |chunk| out = chunk }
    assert_equal("echo: ping", out)
  end

  def test_replies_consumed_in_order
    engine = E.new(replies: %w[first second])
    seen = []
    engine.stream([{ role: "user", content: "a" }]) { |c| seen << c }
    engine.stream([{ role: "user", content: "b" }]) { |c| seen << c }
    assert_equal(%w[first second], seen)
  end

  def test_raises_when_replies_exhausted
    engine = E.new(replies: ["only"])
    engine.stream([{ role: "user", content: "x" }]) { |_| }
    assert_raise_message(/out of scripted replies/) do
      engine.stream([{ role: "user", content: "y" }]) { |_| }
    end
  end

  def test_reset_restarts_index
    engine = E.new(replies: ["a", "b"])
    engine.stream([{ role: "user", content: "1" }]) { |_| }
    engine.reset
    out = nil
    engine.stream([{ role: "user", content: "2" }]) { |chunk| out = chunk }
    assert_equal("a", out)
  end

  def test_close_is_noop
    engine = E.new(replies: ["x"])
    assert_nothing_raised { engine.close }
  end

  def test_fixed_reply_does_not_require_messages
    engine = E.new(replies: ["fixed"])
    out = nil
    engine.stream([]) { |chunk| out = chunk }
    assert_equal("fixed", out)
  end
end
