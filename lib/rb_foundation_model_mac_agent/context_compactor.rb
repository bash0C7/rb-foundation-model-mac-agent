# frozen_string_literal: true

module RbFoundationModelMacAgent
  module ContextCompactor
    HEAD_LINES = 10
    TAIL_LINES = 5
    KEEP_FULL = 3

    module_function

    def compact(messages, system_prompt_size:, target_tokens:)
      return "" if messages.empty?

      rendered = messages.map { |m| render_full(m) }
      budget = [target_tokens - (system_prompt_size / 3), 100].max
      return rendered.join("\n") if total_tokens(rendered) <= budget

      keep_full_from = [messages.length - KEEP_FULL, 0].max
      rendered = messages.each_with_index.map do |m, i|
        i >= keep_full_from ? render_full(m) : render_squeezed(m)
      end
      return rendered.join("\n") if total_tokens(rendered) <= budget

      rendered.shift while rendered.length > 1 && total_tokens(rendered) > budget
      return rendered.first if total_tokens(rendered) <= budget
      truncate_bytes(rendered.first, budget * 3)
    end

    def truncate_bytes(text, max_bytes)
      marker = "\n...[truncated]...\n"
      keep = max_bytes - marker.bytesize
      head = text.byteslice(0, keep * 2 / 3).scrub("")
      tail = text.byteslice(-(keep / 3), keep / 3).scrub("")
      "#{head}#{marker}#{tail}"
    end

    def render_full(msg)
      "#{msg[:role]}: #{msg[:content]}"
    end

    def render_squeezed(msg)
      content = msg[:content]
      if (m = content.match(/```tool_call\n(.*?)\n```/m))
        body = m[1]
        name = body[/name:\s*(\S+)/, 1]
        args = body.scan(/(\w+):[ \t]*(\S+)/).reject { |k, _| k == "name" || k == "args" }
        args_str = args.map { |k, v| "#{k}=#{v}" }.join(", ")
        return "#{msg[:role]}: [tool_call: #{name}(#{args_str})]"
      end
      if (m = content.match(/```tool_result\n(.*?)\n```/m))
        body = m[1]
        if (cm = body.match(/content:\s*\|[-+]?\n(.*)/m))
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
      if content.bytesize > 800
        return "#{msg[:role]}: #{content[0, 400]}...[truncated]...#{content[-200..]}"
      end
      "#{msg[:role]}: #{content}"
    end

    def rough_tokens(text)
      text.to_s.bytesize / 3
    end

    def total_tokens(rendered)
      rendered.sum { |s| rough_tokens(s) }
    end
  end
end
