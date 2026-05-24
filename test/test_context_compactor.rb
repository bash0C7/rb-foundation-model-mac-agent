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

  def test_preserves_last_three_entries_in_full
    # 5 entries: old pair (0,1) squeezed when over budget, last 3 (2,3,4) kept full
    long = "x" * 4000
    messages = [
      { role: "user", content: "old request" },
      { role: "assistant", content: "```tool_call\nname: fs.read\nargs:\n  path: ./old.rb\n```" },
      { role: "user", content: "[recent context]" },
      { role: "assistant", content: "```tool_call\nname: fs.read\nargs:\n  path: ./now.rb\n```" },
      { role: "user", content: "```tool_result\nname: fs.read\nok: true\ncontent: #{long}\n```" },
    ]
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 1470)
    # last 3 entries kept full (not squeezed)
    assert_includes(out, "[recent context]", "index 2 (recent pair start) must be full")
    assert_includes(out, "./now.rb",         "index 3 (recent tool_call) must be full")
    assert_includes(out, long[0, 200],       "index 4 (most-recent tool_result content head) preserved")
    # old assistant tool_call was squeezed to short repr
    assert_includes(out, "[tool_call: fs.read(path=./old.rb)]",
                    "index 1 (old tool_call) must be squeezed")
  end

  def test_squeezes_only_entries_before_last_three
    messages = (0..6).map do |i|
      role = i.even? ? "user" : "assistant"
      content = i < 4 ? "```tool_call\nname: fs.read\nargs:\n  path: ./f#{i}.rb\n```" : "msg #{i} " * 27
      { role: role, content: content }
    end
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 300)
    # indexes 4, 5, 6 are within the keep-full-3 window — must appear verbatim
    assert_includes(out, "msg 4")
    assert_includes(out, "msg 5")
    assert_includes(out, "msg 6")
    # indexes 0..3 either squeezed or dropped, but if present must be squeeze repr
    if out.include?("f3.rb")
      assert_includes(out, "[tool_call: fs.read(path=./f3.rb)]")
    end
  end

  def test_truncates_long_tool_result_content_when_over_budget
    # tool_result at index 2 (older than the last-3 window), should be squeezed
    older_long = (1..300).map { |i| "line #{i}" }.join("\n")
    messages = [
      { role: "user", content: "first" },
      { role: "assistant", content: "```tool_call\nname: fs.read\nargs:\n  path: ./old.rb\n```" },
      { role: "user", content: "```tool_result\nname: fs.read\nok: true\ncontent: |\n  #{older_long}\n```" },
      { role: "user", content: "next" },
      { role: "assistant", content: "next answer" },
      { role: "user", content: "go" },
    ]
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 400)
    assert_includes(out, "truncated", "long tool_result content (old, index 2) should be truncated")
    assert(out.bytesize / 3 <= 400 + 200, "compacted size should not exceed target by much")
  end

  def test_drops_oldest_turn_when_still_over_budget
    messages = (1..10).map do |i|
      role = i.even? ? "user" : "assistant"
      { role: role, content: "turn #{i} " * 100 }
    end
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 300)
    assert_includes(out, "turn 10", "latest turn must still be present")
    assert(!out.include?("turn 1 turn 1 turn 1"), "oldest turns should be dropped")
  end

  def test_short_tool_call_representation
    description = "# " + ("description of what fs.read does " * 8)
    tool_call_content = "```tool_call\nname: fs.read\nargs:\n  path: ./x.rb\n#{description}\n```"
    messages = [
      { role: "assistant", content: tool_call_content },
      { role: "user", content: "filler 1" },
      { role: "assistant", content: "filler 2" },
      { role: "user", content: "latest" },
    ]
    # 4 entries: last 3 (filler1, filler2, latest) kept full, index 0 squeezed
    out = C.compact(messages, system_prompt_size: 300, target_tokens: 200)
    assert_includes(out, "[tool_call: fs.read(path=./x.rb)]", "old tool_call should be compressed to short repr")
  end
end
