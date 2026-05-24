# frozen_string_literal: true

require "yaml"
require_relative "fs_tool"

module RbFoundationModelMacAgent
  module ToolCall
    FENCE_RE  = /```\w*\n(.*?)\n```/m
    BANNER_RE = /\A(?:tool_call|tool_use)\s*\n/i
    NAME_RE   = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/

    module_function

    def parse(text)
      text.to_s.scan(FENCE_RE).each do |(body)|
        body = body.sub(BANNER_RE, "")
        parsed = safe_yaml_load(body)
        next unless parsed.is_a?(Hash)
        next unless parsed["name"].is_a?(String) && parsed["name"].match?(NAME_RE)
        return parsed
      end
      nil
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

    def render_result(name, result)
      payload = { "name" => name, "ok" => result[:ok] }
      if result[:ok]
        payload["content"] = result[:content].to_s
      else
        payload["error"] = result[:error].to_s
      end
      "```tool_result\n#{payload.to_yaml.sub(/\A---\n/, '')}```"
    end

    def safe_yaml_load(body)
      YAML.safe_load(body, permitted_classes: [Symbol])
    rescue Psych::SyntaxError
      nil
    end
  end
end
