# frozen_string_literal: true

require_relative "test_helper"

class TestAppleFmEngine < Test::Unit::TestCase
  def setup
    @engine = RbFoundationModelMacAgent::AppleFmEngine.new(system_prompt: "You answer in one short sentence.")
  rescue AppleFoundationModel::UnavailableError => e
    omit "Apple Intelligence not available: #{e.message}"
  end

  def teardown
    @engine&.close
  end

  def test_stream_yields_chunks_and_returns_their_concatenation
    chunks = []
    result = @engine.stream([{ role: "user", content: "Say hello." }]) { |c| chunks << c }
    assert_false(chunks.empty?)
    assert_equal(chunks.join, result)
    assert_equal(Encoding::UTF_8, result.encoding)
  end

  def test_reset_keeps_engine_usable
    @engine.stream([{ role: "user", content: "Remember the number 42." }]) { |_| }
    @engine.reset
    out = +""
    @engine.stream([{ role: "user", content: "Say OK." }]) { |c| out << c }
    assert_false(out.empty?)
  end

  def test_next_prompt_runs_right_after_a_fence_cancel
    first = @engine.stream([{ role: "user", content: "Write a Ruby hello world program in a fenced code block, then explain it in detail." }]) { |_| }
    block = first.match(RbFoundationModelMacAgent::AppleFmEngine::FENCE_BLOCK_RE)
    assert_not_nil(block, first)
    assert_operator(block.post_match.length, :<, 40, "stream must stop at the closing fence, got #{block.post_match.inspect}")
    second = +""
    @engine.stream([{ role: "user", content: "Say OK." }]) { |c| second << c }
    assert_false(second.empty?)
  end

  def test_recovers_from_real_context_overflow
    builds = 0
    engine = RbFoundationModelMacAgent::AppleFmEngine.new(
      system_prompt: "You answer in one short sentence.",
      session_builder: ->(instr) { builds += 1; AppleFoundationModel::Session.new(instructions: instr) },
    )
    long = "Ruby is a dynamic programming language with a focus on simplicity. " * 1000
    messages = [{ role: "user", content: "Summarize the following text in one sentence.\n#{long}" }]
    out = +""
    engine.stream(messages) { |c| out << c }
    assert_operator(builds, :>=, 2, "the overflow must trigger a compacted retry on a new session")
    assert_false(out.empty?)
  ensure
    engine&.close
  end
end

class FakeOverflowSession
  attr_reader :inputs, :close_calls

  def initialize(behaviors:)
    @behaviors = behaviors.dup
    @inputs = []
    @close_calls = 0
  end

  def stream_response(to:, stop_at: nil)
    @inputs << to
    behavior = @behaviors.shift
    raise "no behavior" unless behavior
    if behavior[:type] == :overflow
      raise AppleFoundationModel::GenerationError,
            "Content contains 12069 tokens, which exceeds the maximum allowed context size of 8192."
    end
    behavior[:chunks].each { |c| yield c }
    behavior[:chunks].join
  end

  def close
    @close_calls += 1
  end

  def cancel_stream; end
end

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
  def engine_with(fake)
    RbFoundationModelMacAgent::AppleFmEngine.new(system_prompt: "system", session_builder: ->(_) { fake })
  end

  def test_engine_retries_once_on_overflow
    fake = FakeOverflowSession.new(behaviors: [
      { type: :overflow },
      { type: :stream, chunks: ["recovered", " ", "output"] },
    ])
    result = engine_with(fake).stream([{ role: "user", content: "hello" }]) { |_| }
    assert_equal("recovered output", result)
    assert_equal(2, fake.inputs.size)
    assert_equal(1, fake.close_calls, "old session should be closed before rebuild")
  end

  def test_engine_raises_after_max_retries
    fake = FakeOverflowSession.new(behaviors: Array.new(3) { { type: :overflow } })
    assert_raise(AppleFoundationModel::GenerationError) do
      engine_with(fake).stream([{ role: "user", content: "hello" }]) { |_| }
    end
    assert_equal(3, fake.inputs.size)
  end

  def test_each_retry_compacts_to_a_smaller_input
    fake = FakeOverflowSession.new(behaviors: [
      { type: :overflow },
      { type: :overflow },
      { type: :stream, chunks: ["ok"] },
    ])
    messages = [{ role: "user", content: "x" * 30_000 }]
    engine_with(fake).stream(messages) { |_| }
    first_retry, second_retry = fake.inputs[1], fake.inputs[2]
    assert_operator(first_retry.bytesize, :<, 30_000)
    assert_operator(second_retry.bytesize, :<, first_retry.bytesize)
  end

  def test_engine_cancels_after_first_complete_tool_call_block
    fake = FakeCancellableSession.new(chunks: [
      "```tool_call\n",
      "name: fs.read\n",
      "args:\n  key: ./sample.rb\n",
      "```\n",
      "```tool_call\n",
      "name: fs.write\n",
      "```\n",
    ])
    engine_with(fake).stream([{ role: "user", content: "hi" }]) { |_| }
    assert_equal(1, fake.cancel_calls)
    assert_equal(4, fake.chunks_yielded)
  end

  def test_engine_cancels_after_first_complete_fenced_block_of_any_language
    fake = FakeCancellableSession.new(chunks: [
      "```ruby\n",
      "fs.read \"./sample.rb\"\n",
      "```\n",
      "```ruby\n",
      "fs.read \"./sample.rb\"\n",
      "```\n",
    ])
    engine_with(fake).stream([{ role: "user", content: "hi" }]) { |_| }
    assert_equal(1, fake.cancel_calls)
    assert_equal(3, fake.chunks_yielded)
  end

  def test_engine_cancels_even_when_closing_fence_lacks_trailing_newline
    fake = FakeCancellableSession.new(chunks: [
      "```ruby\n",
      "fs.read \"./x\"\n",
      "```",
      "```ruby\n",
      "more\n",
      "```\n",
    ])
    engine_with(fake).stream([{ role: "user", content: "hi" }]) { |_| }
    assert_equal(1, fake.cancel_calls)
    assert_operator(fake.chunks_yielded, :<=, 4)
  end

  def test_engine_cancels_when_buffer_exceeds_max_stream_bytes
    big_chunk = "x" * 1024
    fake = FakeCancellableSession.new(chunks: ["```ruby\n", big_chunk, big_chunk, big_chunk, big_chunk, "more\n", "```\n"])
    engine_with(fake).stream([{ role: "user", content: "hi" }]) { |_| }
    assert_equal(1, fake.cancel_calls)
    assert_equal(5, fake.chunks_yielded)
  end

  def test_engine_passes_through_non_overflow_error
    fake = Class.new do
      def stream_response(to:, stop_at: nil)
        raise AppleFoundationModel::GenerationError, "some other error"
      end

      def close; end
    end.new
    assert_raise_message("some other error") do
      engine_with(fake).stream([{ role: "user", content: "hi" }]) { |_| }
    end
  end
end
