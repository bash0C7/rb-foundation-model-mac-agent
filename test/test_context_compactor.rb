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
    # tool_call inflated with a large description comment (no key:value pairs) to push full render
    # over the 100-token min-budget clamp. Squeezed form has only path= arg (~11 tokens), so
    # Stage 2 result fits within budget and is returned without Stage 3 dropping it.
    description = "# " + ("description of what fs.read does " * 8)
    tool_call_content = "```tool_call\nname: fs.read\nargs:\n  path: ./x.rb\n#{description}\n```"
    messages = [
      { role: "assistant", content: tool_call_content },
      { role: "user", content: "latest" },
    ]
    # system_prompt_size: 300 => budget = 200 - 100 = 100; full render > 100 => Stage 2 triggers
    out = C.compact(messages, system_prompt_size: 300, target_tokens: 200)
    assert_includes(out, "[tool_call: fs.read(path=./x.rb)]", "old tool_call should be compressed to short repr")
  end
end
