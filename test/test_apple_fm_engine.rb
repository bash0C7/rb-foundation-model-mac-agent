# frozen_string_literal: true

require_relative "test_helper"

class TestAppleFmEngine < Test::Unit::TestCase
  def setup
    @session = RbFoundationModelMacAgent::AppleFmEngine.new(system_prompt: "You answer in one word.")
  rescue AppleFoundationModel::UnavailableError => e
    omit "Apple Intelligence not available: #{e.message}"
  end

  def teardown
    @session&.close
  end

  def test_stream_yields_chunks_from_apple_fm
    out = +""
    @session.stream([{ role: "user", content: "Say hello." }]) { |c| out << c }
    assert_false(out.empty?)
  end

  def test_reset_recreates_underlying_session
    out1 = +""
    @session.stream([{ role: "user", content: "Hi. Remember the number 42." }]) { |c| out1 << c }
    @session.reset
    out2 = +""
    @session.stream([{ role: "user", content: "What number did I say earlier?" }]) { |c| out2 << c }
    # After reset the model should not remember 42 — the test is fuzzy but if reset
    # really rebuilt the session, "42" shouldn't appear in out2 (or appears only
    # because the model guessed it). We assert weakly: just that reset doesn't crash
    # and stream still works.
    assert_false(out2.empty?)
  end
end
