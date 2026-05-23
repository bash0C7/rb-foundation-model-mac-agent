# frozen_string_literal: true

require "yaml"
require_relative "fs_tool"

module RbFoundationModelMacAgent
  module ToolCall
    FENCE_RE = /```tool_call\n(.*?)\n```/m

    module_function

    def parse(text)
      m = text.match(FENCE_RE)
      return nil unless m
      YAML.safe_load(m[1], permitted_classes: [Symbol])
    end

    def dispatch(call, agent_def:, fs_root:, mcp_registry:)
      name = call.fetch("name")
      args = call["args"] || {}
      ns, tool = name.split(".", 2)

      content =
        if ns == "fs"
          raise "tool '#{name}' not allowed" unless agent_def[:allowed_builtin].include?(name)
          FsTool.public_send(tool, **args.transform_keys(&:to_sym), fs_root: fs_root)
        else
          raise "mcp '#{ns}' not allowed" unless agent_def[:allowed_mcp].include?(ns)
          mcp_registry.call(server: ns, tool: tool, args: args)
        end
      { ok: true, content: content }
    rescue StandardError => e
      { ok: false, error: e.message }
    end

    # Render a result hash as the ```tool_result fenced block we inject into
    # the next user message.
    def render_result(name, result)
      payload = { "name" => name, "ok" => result[:ok] }
      if result[:ok]
        payload["content"] = result[:content].to_s
      else
        payload["error"] = result[:error].to_s
      end
      "```tool_result\n#{payload.to_yaml.sub(/\A---\n/, '')}```"
    end
  end
end
