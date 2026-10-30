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
    long = "x" * 4000
    messages = [
      { role: "user", content: "old request" },
      { role: "assistant", content: "```tool_call\nname: fs.read\nargs:\n  path: ./old.rb\n```" },
      { role: "user", content: "[recent context]" },
      { role: "assistant", content: "```tool_call\nname: fs.read\nargs:\n  path: ./now.rb\n```" },
      { role: "user", content: "```tool_result\nname: fs.read\nok: true\ncontent: #{long}\n```" },
    ]
    out = C.compact(messages, system_prompt_size: 200, target_tokens: 1470)
    assert_includes(out, "[recent context]", "index 2 (recent pair start) must be full")
    assert_includes(out, "./now.rb",         "index 3 (recent tool_call) must be full")
    assert_includes(out, long[0, 200],       "index 4 (most-recent tool_result content head) preserved")
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
    assert_includes(out, "msg 4")
    assert_includes(out, "msg 5")
    assert_includes(out, "msg 6")
    if out.include?("f3.rb")
      assert_includes(out, "[tool_call: fs.read(path=./f3.rb)]")
    end
  end

  def test_truncates_long_tool_result_content_when_over_budget
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

  def test_single_oversized_message_is_truncated_to_budget
    huge = "line of a very large file\n" * 2000
    out = C.compact([{ role: "user", content: huge }], system_prompt_size: 300, target_tokens: 1000)
    assert_operator(out.bytesize / 3, :<=, 1000)
    assert(out.start_with?("user: line of a very large file"))
    assert_includes(out, "[truncated]")
  end

  def test_squeezes_tool_result_rendered_with_strip_chomp_indicator
    content = (1..40).map { |i| "row #{i}" }.join("\n")
    tool_result = RbFoundationModelMacAgent::ToolCall.render_result("fs.read", { ok: true, content: content })
    assert_match(/content: \|-\n/, tool_result)
    messages = [
      { role: "user", content: tool_result },
      { role: "user", content: "a" * 700 },
      { role: "assistant", content: "b" * 700 },
      { role: "user", content: "c" * 700 },
    ]
    out = C.compact(messages, system_prompt_size: 0, target_tokens: 800)
    assert_includes(out, "dropped 25 lines")
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
    out = C.compact(messages, system_prompt_size: 300, target_tokens: 200)
    assert_includes(out, "[tool_call: fs.read(path=./x.rb)]", "old tool_call should be compressed to short repr")
  end
end
