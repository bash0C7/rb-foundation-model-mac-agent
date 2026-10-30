# frozen_string_literal: true

require "json"
require "uri"
require "fileutils"
require "mcp"

module RbFoundationModelMacAgent
  class McpRegistry
    GIT_HOSTS = %w[github.com gitlab.com bitbucket.org codeberg.org].freeze

    def initialize(config_path:)
      @config_path = config_path
      @entries = {}
      load_and_connect_all
    end

    def list
      @entries.map do |name, e|
        { name: name, source: e[:source], kind: e[:kind],
          status: e[:status], tool_count: e[:tools].size, error: e[:error] }
      end
    end

    def tools(server)
      @entries.fetch(server, { tools: [] })[:tools]
    end

    def call(server:, tool:, args:)
      e = @entries.fetch(server) { raise "unknown MCP server: #{server}" }
      raise "MCP server '#{server}' is not connected (#{e[:error]})" unless e[:status] == :ok
      result = e[:client].call_tool(name: tool, arguments: args).fetch("result", {})
      text = (result["content"] || []).filter_map { |c| c["text"] if c["type"] == "text" }.join("\n")
      raise "MCP tool #{server}.#{tool} failed: #{text}" if result["isError"]
      text
    end

    def add(name, source = nil, **opts)
      kind = (opts.delete(:kind) || SourceDetector.classify(source)).to_s
      cfg  = { kind: kind, source: source }.merge(opts).compact
      entry = connect_one(name, cfg)
      raise entry[:error] unless entry[:status] == :ok
      disconnect(@entries[name])
      @entries[name] = entry
      save_config
    end

    def remove(name)
      e = @entries.delete(name) { raise "unknown MCP server: #{name}" }
      disconnect(e)
      save_config
    end

    def close_all
      @entries.each_value { |e| disconnect(e) }
    end

    private

    def disconnect(entry)
      entry&.dig(:client)&.transport&.close
    end

    def load_and_connect_all
      read_config.fetch("servers", {}).each do |name, raw|
        @entries[name] = connect_one(name, raw.transform_keys(&:to_sym))
      end
    end

    def read_config
      return { "servers" => {} } unless File.file?(@config_path)
      JSON.parse(File.read(@config_path))
    end

    def save_config
      FileUtils.mkdir_p(File.dirname(@config_path))
      servers = @entries.transform_values do |e|
        { "kind" => e[:kind].to_s, "source" => e[:source], "cmd" => e[:cmd],
          "args" => e[:args], "env" => e[:env], "headers" => e[:headers] }.compact
      end
      File.write(@config_path, JSON.pretty_generate("servers" => servers))
    end

    def connect_one(name, cfg)
      transport = build_transport(cfg)
      client = MCP::Client.new(transport: transport)
      client.connect(client_info: { name: "rb-foundation-model-mac-agent", version: RbFoundationModelMacAgent::VERSION })
      tools = client.tools.map { |t| { name: t.name, description: t.description, input_schema: t.input_schema } }
      cfg.merge(client: client, tools: tools, status: :ok)
    rescue StandardError => e
      transport&.close
      warn "[mcp] connect failed: #{name}: #{e.message}"
      cfg.merge(client: nil, tools: [], status: :error, error: e.message)
    end

    def build_transport(cfg)
      case cfg[:kind].to_s
      when "http"
        MCP::Client::HTTP.new(url: cfg[:source], headers: cfg[:headers] || {})
      when "stdio"
        MCP::Client::Stdio.new(command: cfg.fetch(:cmd), args: cfg[:args] || [], env: cfg[:env])
      when "git", "filepath"
        cmd, args, env = SourceDetector.resolve(kind: cfg[:kind].to_s, source: cfg[:source])
        MCP::Client::Stdio.new(command: cmd, args: args, env: env)
      else
        raise "unknown MCP kind: #{cfg[:kind]}"
      end
    end

    module SourceDetector
      module_function

      def classify(source)
        s = source.to_s.strip
        raise "SOURCE is empty" if s.empty?
        return "git"      if git_repo?(s)
        return "http"     if http_endpoint?(s)
        return "filepath" if filepath?(s)
        raise "cannot classify MCP source: #{source.inspect}"
      end

      def git_repo?(s)
        return true if s.start_with?("git@")
        return true if s.end_with?(".git")
        http_like?(s) && McpRegistry::GIT_HOSTS.include?(URI.parse(s).host)
      rescue URI::InvalidURIError
        false
      end

      def http_endpoint?(s)
        http_like?(s) && !McpRegistry::GIT_HOSTS.include?(URI.parse(s).host)
      rescue URI::InvalidURIError
        false
      end

      def filepath?(s)
        File.directory?(File.expand_path(s))
      end

      def http_like?(s)
        s.start_with?("http://", "https://")
      end

      def resolve(kind:, source:)
        case kind
        when "filepath"
          resolve_filepath(File.expand_path(source))
        when "git"
          raise "git MCP sources are not supported; clone the repository and add its local directory"
        end
      end

      def resolve_filepath(path)
        raise "MCP path does not exist: #{path}" unless File.directory?(path)
        if File.file?(File.join(path, "package.json")) && File.file?(File.join(path, "package-lock.json"))
          pkg = JSON.parse(File.read(File.join(path, "package.json")))
          bin_relpath = pkg.fetch("bin").first.last.to_s
          ["node", [File.join(path, bin_relpath)], nil]
        elsif File.file?(File.join(path, "pyproject.toml"))
          script = File.read(File.join(path, "pyproject.toml"))[/\[project\.scripts\]\s*\n([\w-]+)\s*=/, 1]
          raise "pyproject.toml has no [project.scripts] script" unless script
          ["uvx", ["--from", path, script], nil]
        elsif File.file?(File.join(path, "Gemfile")) && !Dir.glob(File.join(path, "*.gemspec")).empty?
          gemspec_path = Dir.glob(File.join(path, "*.gemspec")).first
          execs = File.read(gemspec_path).scan(/spec\.executables\s*=\s*\[([^\]]+)\]/).flatten.first
          exec_name = execs.scan(/["']([^"']+)["']/).flatten.first if execs
          raise "Gemfile present but gemspec has no spec.executables" unless exec_name
          ["bundle", ["exec", File.join(path, "exe", exec_name)], { "BUNDLE_GEMFILE" => File.join(path, "Gemfile") }]
        else
          raise "no MCP marker (package.json+lock / pyproject.toml / Gemfile+gemspec) found in #{path}"
        end
      end
    end
  end
end
