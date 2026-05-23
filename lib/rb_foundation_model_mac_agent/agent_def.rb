# frozen_string_literal: true

require "yaml"

module RbFoundationModelMacAgent
  module AgentDef
    DEFAULTS = {
      model: "default",
      fs_root: ".",
      allowed_mcp: [].freeze,
      allowed_builtin: [].freeze,
      max_iters: 8,
    }.freeze

    FRONTMATTER_RE = /\A---\n(.*?)\n---\n(.*)\z/m

    module_function

    # Returns a Hash with keys :name :engine :model :fs_root :allowed_mcp
    # :allowed_builtin :max_iters :body. Project-local definitions win when
    # the same name exists in both dirs.
    def load(name, gem_agents_dir:, project_agents_dir:)
      path = resolve_path(name, gem_agents_dir, project_agents_dir)
      raise "agent '#{name}' not found in #{project_agents_dir} or #{gem_agents_dir}" unless path
      parse_file(path)
    end

    # Returns the list of agent names available across both dirs, deduped
    # (project local wins on dup).
    def list(gem_agents_dir:, project_agents_dir:)
      names = []
      [gem_agents_dir, project_agents_dir].each do |dir|
        next unless dir && File.directory?(dir)
        Dir.glob(File.join(dir, "*.md")).each do |f|
          names << File.basename(f, ".md")
        end
      end
      names.uniq.sort
    end

    def resolve_path(name, gem_dir, project_dir)
      project_path = File.join(project_dir, "#{name}.md") if project_dir
      return project_path if project_path && File.file?(project_path)
      gem_path = File.join(gem_dir, "#{name}.md") if gem_dir
      return gem_path if gem_path && File.file?(gem_path)
      nil
    end

    def parse_file(path)
      raw = File.read(path)
      m = raw.match(FRONTMATTER_RE)
      raise "agent file missing frontmatter: #{path}" unless m
      fm = YAML.safe_load(m[1]) || {}
      body = m[2]

      validate!(fm, path)

      DEFAULTS.merge(
        name:            fm.fetch("name"),
        engine:          fm.fetch("engine"),
        model:           fm["model"]           || DEFAULTS[:model],
        fs_root:         fm["fs_root"]         || DEFAULTS[:fs_root],
        allowed_mcp:     fm["allowed_mcp"]     || DEFAULTS[:allowed_mcp],
        allowed_builtin: fm["allowed_builtin"] || DEFAULTS[:allowed_builtin],
        max_iters:       fm["max_iters"]       || DEFAULTS[:max_iters],
        body:            body,
      )
    end

    def validate!(fm, path)
      raise "agent file #{path} missing 'name'"   unless fm["name"].is_a?(String)
      raise "agent file #{path} missing 'engine'" unless fm["engine"].is_a?(String)
      unless %w[apple-fm ollama echo].include?(fm["engine"])
        raise "agent file #{path} has unknown engine: #{fm["engine"]}"
      end
    end
  end
end
