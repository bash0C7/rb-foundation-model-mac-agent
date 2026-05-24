# frozen_string_literal: true

require_relative "test_helper"
require "rb_foundation_model_mac_agent/context_compactor"

class TestContextCompactor < Test::Unit::TestCase
  C = RbFoundationModelMacAgent::ContextCompactor

  def test_returns_last_user_input_when_only_one_message
    messages = [{ role: "user", content: "hello" }]
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 3500)
    assert_includes(out, "hello")
  end

  def test_preserves_recent_pair_full
    messages = [
      { role: "user", content: "old request" },
      { role: "assistant", content: "old answer" },
      { role: "user", content: "[tool_result]\nname: fs.read\nok: true\ncontent: foo" },
      { role: "user", content: "new request" },
    ]
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 3500)
    assert_includes(out, "new request")
    assert_includes(out, "old answer")  # recent pair preserved
  end

  def test_truncates_long_tool_result_content_when_over_budget
    long = (1..200).map { |i| "line #{i}" }.join("\n")
    messages = [
      { role: "user", content: "first" },
      { role: "assistant", content: "```tool_call\nname: fs.read\nargs:\n  path: ./big.rb\n```" },
      { role: "user", content: "```tool_result\nname: fs.read\nok: true\ncontent: |\n  #{long}\n```" },
      { role: "user", content: "go" },
    ]
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 400)
    assert_includes(out, "truncated", "long tool_result content should be truncated marker")
    assert(out.bytesize / 3 <= 400 + 200, "compacted size should not exceed target by much")
  end

  def test_drops_oldest_turn_when_still_over_budget
    messages = (1..10).map.with_index do |_, i|
      role = i.even? ? "user" : "assistant"
      { role: role, content: "turn #{i} " * 100 }
    end
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 300)
    # Latest turn must still be present
    assert_includes(out, "turn 9")
    # Oldest turn should be dropped
    assert(!out.include?("turn 0"), "oldest turn should be dropped")
  end

  def test_short_tool_call_representation
    messages = [
      { role: "user", content: "first" },
      { role: "assistant", content: "```tool_call\nname: fs.read\nargs:\n  path: ./x.rb\n```" },
      { role: "user", content: "ok" },
      { role: "assistant", content: "second" },
      { role: "user", content: "next" },
      { role: "assistant", content: "third" },
      { role: "user", content: "latest" },
    ]
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 400)
    # Old tool_call should be compressed to short repr
    assert(
      out.include?("[tool_call: fs.read(path=./x.rb)]") || !out.include?("```tool_call"),
      "old tool_call should be compressed",
    )
  end
end
