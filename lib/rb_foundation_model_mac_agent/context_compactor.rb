# frozen_string_literal: true

module RbFoundationModelMacAgent
  module ContextCompactor
    HEAD_LINES = 10
    TAIL_LINES = 5

    module_function

    # messages: [{role:, content:}, ...]
    # system_prompt_size: rough chars/bytes of the system prompt (already in Apple FM)
    # target_tokens: budget for the compacted output
    def compact(messages, system_prompt_size:, target_tokens:)
      return "" if messages.empty?

      budget = target_tokens - rough_tokens(system_prompt_size_chars: system_prompt_size)
      budget = 100 if budget < 100  # always leave room

      # Stage 2: squeeze all entries except the last one (always applied)
      # Last entry stays full; older tool_call/tool_result/long entries are compressed
      last_idx = messages.length - 1
      rendered = messages.each_with_index.map do |m, i|
        i == last_idx ? render_full(m) : render_squeezed(m)
      end
      return rendered.join("\n") if total_tokens(rendered) <= budget

      # Stage 3: drop oldest until under budget
      while rendered.length > 1 && total_tokens(rendered) > budget
        rendered.shift
      end
      rendered.join("\n")
    end

    # --- helpers ---

    def render_full(msg)
      "#{msg[:role]}: #{msg[:content]}"
    end

    def render_squeezed(msg)
      content = msg[:content]
      # tool_call fence → short repr
      if (m = content.match(/```tool_call\n(.*?)\n```/m))
        body = m[1]
        name = body[/name:\s*(\S+)/, 1]
        args = body.scan(/(\w+):\s*(\S+)/).reject { |k, _| k == "name" || k == "args" }
        args_str = args.map { |k, v| "#{k}=#{v}" }.join(", ")
        return "#{msg[:role]}: [tool_call: #{name}(#{args_str})]"
      end
      # tool_result fence → head/tail
      if (m = content.match(/```tool_result\n(.*?)\n```/m))
        body = m[1]
        if (cm = body.match(/content:\s*\|\n(.*)/m))
          lines = cm[1].split("\n")
          if lines.length > HEAD_LINES + TAIL_LINES
            head = lines.first(HEAD_LINES).join("\n")
            tail = lines.last(TAIL_LINES).join("\n")
            dropped = lines.length - HEAD_LINES - TAIL_LINES
            squeezed = "[tool_result: #{body.lines.first&.chomp}; content head/tail, dropped #{dropped} lines]\n#{head}\n...[truncated #{dropped} lines]...\n#{tail}"
            return "#{msg[:role]}: #{squeezed}"
          end
        end
        return "#{msg[:role]}: [tool_result: #{body.lines.first(2).join.chomp}]"
      end
      # Long plain content → truncate
      if content.bytesize > 800
        return "#{msg[:role]}: #{content[0, 400]}...[truncated]...#{content[-200..]}"
      end
      "#{msg[:role]}: #{content}"
    end

    def rough_tokens(text = nil, system_prompt_size_chars: nil)
      if system_prompt_size_chars
        return system_prompt_size_chars / 3
      end
      text.to_s.bytesize / 3
    end

    def total_tokens(rendered)
      rendered.sum { |s| rough_tokens(s) }
    end
  end
end
