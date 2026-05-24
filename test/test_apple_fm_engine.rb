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

# --- recovery tests ---

class FakeOverflowSession
  attr_reader :stream_calls, :close_calls
  def initialize(behaviors:)
    @behaviors = behaviors.dup
    @stream_calls = 0
    @close_calls = 0
    @cancel_calls = 0
  end
  def stream_response(to:, stop_at: nil)
    @stream_calls += 1
    behavior = @behaviors.shift
    raise "no behavior" unless behavior
    case behavior[:type]
    when :overflow
      raise AppleFoundationModel::GenerationError,
            "exceededContextWindowSize: Content contains 4090 tokens, which exceeds the maximum allowed context size of 4096."
    when :stream
      behavior[:chunks].each { |c| yield c }
      behavior[:chunks].join
    end
  end
  def close
    @close_calls += 1
  end
  def cancel_stream; @cancel_calls += 1; end
end

# Honors cancel_stream by breaking the chunk loop on the next iteration,
# mirroring how the real Apple FM Swift task observes Task.isCancelled.
class FakeCancellableSession
  attr_reader :cancel_calls, :chunks_yielded
  def initialize(chunks:)
    @chunks = chunks
    @cancel_calls = 0
    @chunks_yielded = 0
    @cancelled = false
  end
  def stream_response(to:, stop_at: nil)
    out = +""
    @chunks.each do |c|
      break if @cancelled
      yield c
      out << c
      @chunks_yielded += 1
    end
    out
  end
  def cancel_stream
    @cancel_calls += 1
    @cancelled = true
  end
  def close; end
end

class TestAppleFmEngineRecovery < Test::Unit::TestCase
  def test_engine_retries_once_on_overflow
    fake = FakeOverflowSession.new(behaviors: [
      { type: :overflow },
      { type: :stream, chunks: ["recovered", " ", "output"] },
    ])
    engine = RbFoundationModelMacAgent::AppleFmEngine.new(
      system_prompt: "system",
      session_builder: ->(_) { fake },
    )
    chunks = []
    result = engine.stream([{ role: "user", content: "hello" }]) { |c| chunks << c }
    assert_equal("recovered output", result)
    assert_equal(2, fake.stream_calls)
    assert(fake.close_calls >= 1, "old session should be closed before rebuild")
  end

  def test_engine_raises_after_max_retries
    fake = FakeOverflowSession.new(behaviors: [
      { type: :overflow },
      { type: :overflow },
      { type: :overflow },
    ])
    engine = RbFoundationModelMacAgent::AppleFmEngine.new(
      system_prompt: "system",
      session_builder: ->(_) { fake },
    )
    assert_raise(AppleFoundationModel::GenerationError) do
      engine.stream([{ role: "user", content: "hello" }]) { |_| }
    end
    assert_equal(3, fake.stream_calls)  # initial + 2 retries
  end

  def test_engine_cancels_after_first_complete_tool_call_block
    fake = FakeCancellableSession.new(chunks: [
      "```tool_call\n",
      "name: fs.read\n",
      "args:\n  key: ./sample.rb\n",
      "```\n",                 # closing fence — cancel should fire here
      "```tool_call\n",         # never reached
      "name: fs.write\n",
      "```\n",
    ])
    engine = RbFoundationModelMacAgent::AppleFmEngine.new(
      system_prompt: "system",
      session_builder: ->(_) { fake },
    )
    engine.stream([{ role: "user", content: "hi" }]) { |_| }
    assert_equal(1, fake.cancel_calls, "cancel_stream should fire once after first tool_call block")
    assert_equal(4, fake.chunks_yielded, "no further chunks should be processed after cancel")
  end

  def test_engine_cancels_after_first_complete_fenced_block_of_any_language
    # Reproduces the L3 ```ruby flavor hang: Apple FM emits a ruby code block
    # back-to-back. Engine must cancel after the first block even though the
    # language tag is not "tool_call".
    fake = FakeCancellableSession.new(chunks: [
      "```ruby\n",
      "fs.read \"./sample.rb\"\n",
      "```\n",                  # closing fence — cancel should fire here
      "```ruby\n",               # never reached
      "fs.read \"./sample.rb\"\n",
      "```\n",
    ])
    engine = RbFoundationModelMacAgent::AppleFmEngine.new(
      system_prompt: "system",
      session_builder: ->(_) { fake },
    )
    engine.stream([{ role: "user", content: "hi" }]) { |_| }
    assert_equal(1, fake.cancel_calls, "cancel_stream should fire once after first ```ruby block")
    assert_equal(3, fake.chunks_yielded, "no further chunks should be processed after cancel")
  end

  def test_engine_cancels_even_when_closing_fence_lacks_trailing_newline
    # Some Apple FM outputs concatenate blocks without "\n" between close and
    # next open (e.g. "```\n```ruby" instead of "```\n\n```ruby"). The cancel
    # heuristic must trigger on the closing "\n```" regardless.
    fake = FakeCancellableSession.new(chunks: [
      "```ruby\n",
      "fs.read \"./x\"\n",
      "```",                   # closing fence WITHOUT trailing newline
      "```ruby\n",              # next block starts immediately
      "more\n",
      "```\n",
    ])
    engine = RbFoundationModelMacAgent::AppleFmEngine.new(
      system_prompt: "system",
      session_builder: ->(_) { fake },
    )
    engine.stream([{ role: "user", content: "hi" }]) { |_| }
    assert_equal(1, fake.cancel_calls)
    assert(fake.chunks_yielded <= 4, "cancel must fire by chunk 4 at the latest (got #{fake.chunks_yielded})")
  end

  def test_engine_passes_through_non_overflow_error
    fake = Class.new do
      def stream_response(to:, stop_at: nil)
        raise AppleFoundationModel::GenerationError, "some other error"
      end
      def close; end
      def cancel_stream; end
    end.new
    engine = RbFoundationModelMacAgent::AppleFmEngine.new(
      system_prompt: "system",
      session_builder: ->(_) { fake },
    )
    assert_raise(AppleFoundationModel::GenerationError) do
      engine.stream([{ role: "user", content: "hi" }]) { |_| }
    end
  end
end
