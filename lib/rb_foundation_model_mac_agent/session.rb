# frozen_string_literal: true

require_relative "tool_call"
require_relative "scripted_engine"
require_relative "apple_fm_engine"
require_relative "ollama_engine"
require_relative "input_preprocessor"

module RbFoundationModelMacAgent
  class Session
    attr_reader :messages, :system_prompt

    # engine: keyword exists primarily for tests (inject ScriptedEngine).
    # Production callers omit it and let the factory choose.
    def initialize(agent_def:, mcp_registry:, engine: nil)
      @agent_def     = agent_def
      @mcp_registry  = mcp_registry
      @fs_root       = File.expand_path(agent_def[:fs_root])
      @system_prompt = build_system_prompt(agent_def, mcp_registry)
      @engine        = engine || build_engine(agent_def, @system_prompt)
      @messages      = []
      @preprocessor  = build_preprocessor(agent_def)
    end

    def turn(user_input, display:)
      original_lang = "en"
      if @preprocessor
        pre = @preprocessor.preprocess(user_input)
        user_input = pre[:text]
        original_lang = pre[:original_lang]
      end

      @messages << { role: "user", content: user_input }
      iters = @agent_def[:max_iters]
      iters.times do
        assistant_text = stream_and_show(@messages, display)
        @messages << { role: "assistant", content: assistant_text }

        call = ToolCall.parse(assistant_text)
        if call.nil?
          if @preprocessor && original_lang == "ja"
            translated = @preprocessor.postprocess(assistant_text, original_lang: original_lang)
            if translated != assistant_text
              display.dialog(translated, style: :assistant)
            end
          end
          return
        end

        result = ToolCall.dispatch(
          call,
          agent_def: @agent_def, fs_root: @fs_root, mcp_registry: @mcp_registry,
        )
        inject = ToolCall.render_result(call.fetch("name"), result)
        @messages << { role: "user", content: inject }
        display.dialog(inject, style: :tool_result)
      end
      display.dialog("max iterations (#{iters}) exceeded; stopping.", style: :warn)
    end

    def reset
      @messages.clear
      @engine.reset
    end

    def close
      @engine.close
    end

    private

    def stream_and_show(messages, display)
      buf = +""
      slot = display.open_live(style: :assistant)
      @engine.stream(messages) { |chunk| buf << chunk; slot.update(buf) }
      slot.commit
      buf
    end

    def build_preprocessor(agent_def)
      return nil unless agent_def[:preprocess_input] == "ja-en-roundtrip"
      InputPreprocessor.new
    end

    def build_engine(agent_def, system_prompt)
      case agent_def.fetch(:engine)
      when "apple-fm" then AppleFmEngine.new(system_prompt: system_prompt)
      when "ollama"   then OllamaEngine.new(model: agent_def.fetch(:model), system_prompt: system_prompt)
      when "scripted" then ScriptedEngine.new(replies: agent_def[:scripted_replies])
      else raise "unknown engine: #{agent_def[:engine]}"
      end
    end

    def build_system_prompt(agent_def, mcp_registry)
      return agent_def[:body] if agent_def[:engine] == "scripted"
      "#{agent_def[:body]}\n\n## Available tools\n\n#{render_tools(agent_def, mcp_registry)}\n\n#{tool_call_format_guide}"
    end

    def render_tools(agent_def, mcp_registry)
      lines = []
      agent_def[:allowed_builtin].each do |name|
        lines << "- #{name}"
      end
      agent_def[:allowed_mcp].each do |srv|
        mcp_registry.tools(srv).each do |t|
          lines << "- #{srv}.#{t[:name]} — #{t[:description]}"
        end
      end
      lines.empty? ? "(no tools available)" : lines.join("\n")
end

    def tool_call_format_guide
      <<~GUIDE
        Tool call format:
        ```tool_call
        name: <ns>.<tool>
        args:
          key: value
        ```
        Rules:
        - Emit at most ONE tool_call per turn, then STOP generating.
        - For final answer, omit any tool_call block.
        - fs.* paths resolve to workspace root.

        Example — to read a file:
        ```tool_call
        name: fs.read
        args:
          path: ./sample.rb
        ```
      GUIDE
    end
  end
end
