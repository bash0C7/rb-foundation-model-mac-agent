# frozen_string_literal: true

require "baslash"
require "fileutils"
require "json"
require "yaml"
require_relative "agent_def"
require_relative "mcp_registry"
require_relative "session"
require_relative "version"

module RbFoundationModelMacAgent
  module CLI
    DEFAULT_AGENT = "yamabiko"
    PROJECT_DIR_NAME = ".rb-foundation-model-mac-agent"
    GEM_AGENTS_DIR = File.expand_path("../../agents", __dir__)

    module_function

    def run(argv)
      agent_name = argv.first || DEFAULT_AGENT
      project_dir = ensure_project_dir(Dir.pwd)
      mcp_config  = File.join(project_dir, "mcp.json")
      project_agents = File.join(project_dir, "agents")

      agent_def = AgentDef.load(agent_name,
                                gem_agents_dir: GEM_AGENTS_DIR,
                                project_agents_dir: project_agents)
      registry = McpRegistry.new(config_path: mcp_config)
      session  = Session.new(agent_def: agent_def, mcp_registry: registry)

      at_exit { session.close; registry.close_all }

      start_shell(agent_def: agent_def, registry: registry, session: session,
                  project_agents: project_agents)
    end

    def ensure_project_dir(cwd)
      dir = File.join(cwd, PROJECT_DIR_NAME)
      unless File.directory?(dir)
        FileUtils.mkdir_p(File.join(dir, "agents"))
        File.write(File.join(dir, "mcp.json"), JSON.pretty_generate("servers" => {}))
      end
      dir
    end

    def start_shell(agent_def:, registry:, session:, project_agents:)
      Baslash.run do |shell|
        shell.header do |h|
          h.logo     "✻"
          h.title    "rb-foundation-model-mac-agent"
          h.version  "v#{VERSION}"
          h.subtitle "agent=#{agent_def[:name]} · engine=#{agent_def[:engine]} · #{Dir.pwd}"
        end

        shell.shortcuts_hint "/agents · /tools · /mcp list · /reset · /quit"

        shell.on_submit do |args, ctx|
          line = args.first.to_s
          next if line.strip.empty?
          ctx.state[:phase] = :working
          begin
            session.turn(line, display: ctx.display)
          rescue StandardError => e
            ctx.display.dialog("error: #{e.class}: #{e.message}", style: :warn)
            ctx.logger.error(e.full_message) if ctx.respond_to?(:logger)
          ensure
            ctx.state[:phase] = :idle
          end
        end

        shell.slash(:agents, description: "list available agents") do |_args, ctx|
          names = AgentDef.list(gem_agents_dir: GEM_AGENTS_DIR, project_agents_dir: project_agents)
          ctx.display.dialog(names.join("\n"), style: :result)
        end

        shell.slash(:tools, description: "list tools for the current agent") do |_args, ctx|
          lines = []
          agent_def[:allowed_builtin].each { |n| lines << "- #{n} (built-in)" }
          agent_def[:allowed_mcp].each do |srv|
            registry.tools(srv).each { |t| lines << "- #{srv}.#{t[:name]} — #{t[:description]}" }
          end
          ctx.display.dialog(lines.empty? ? "(no tools)" : lines.join("\n"), style: :result)
        end

        shell.slash(:mcp, description: "manage MCP servers — list | add NAME SOURCE | remove NAME") do |args, ctx|
          sub = args.shift
          case sub
          when "list", nil
            rows = registry.list.map { |r| "- #{r[:name]} (#{r[:kind]}, #{r[:status]}, #{r[:tool_count]} tools) #{r[:source]}" }
            ctx.display.dialog(rows.empty? ? "(no servers)" : rows.join("\n"), style: :result)
          when "add"
            name, source = args
            raise "usage: /mcp add NAME SOURCE" unless name && source
            registry.add(name, source)
            ctx.display.dialog("added #{name}", style: :result)
          when "remove"
            name = args.first
            raise "usage: /mcp remove NAME" unless name
            registry.remove(name)
            ctx.display.dialog("removed #{name}", style: :result)
          else
            ctx.display.dialog("unknown subcommand: #{sub}", style: :warn)
          end
        rescue StandardError => e
          ctx.display.dialog("/mcp error: #{e.message}", style: :warn)
        end

        shell.slash(:reset, description: "clear conversation history") do |_args, ctx|
          session.reset
          ctx.display.dialog("history cleared", style: :result)
        end

        shell.slash(:dump, description: "dump current @messages as YAML") do |_args, ctx|
          ctx.display.dialog(session.messages.to_yaml, style: :result)
        end
      end
    end
  end
end
