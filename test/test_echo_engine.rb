# frozen_string_literal: true

require_relative "test_helper"

class TestEchoEngine < Test::Unit::TestCase
  def test_stream_yields_last_user_content
    engine = RbFoundationModelMacAgent::EchoEngine.new
    out = +""
    engine.stream([{ role: "user", content: "hello world" }]) { |c| out << c }
    assert_equal("hello world", out)
  end

  def test_close_is_safe
    engine = RbFoundationModelMacAgent::EchoEngine.new
    assert_nothing_raised { engine.close }
  end

  def test_reset_is_safe
    assert_nothing_raised { RbFoundationModelMacAgent::EchoEngine.new.reset }
  end
end
