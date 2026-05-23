# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class TestAgentDef < Test::Unit::TestCase
  AD = RbFoundationModelMacAgent::AgentDef

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def test_parse_valid_frontmatter_and_body
    Dir.mktmpdir do |gem_dir|
      write(File.join(gem_dir, "agents", "ruby-coder.md"), <<~MD)
        ---
        name: ruby-coder
        engine: apple-fm
        model: default
        fs_root: .
        allowed_mcp:
          - chiebukuro
        allowed_builtin:
          - fs.read
          - fs.write
        max_iters: 8
        ---
        You are a CRuby 4.x coding assistant.
      MD
      Dir.mktmpdir do |project_dir|
        d = AD.load("ruby-coder", gem_agents_dir: File.join(gem_dir, "agents"),
                                  project_agents_dir: File.join(project_dir, "agents"))
        assert_equal("ruby-coder",                       d[:name])
        assert_equal("apple-fm",                         d[:engine])
        assert_equal("default",                          d[:model])
        assert_equal(".",                                d[:fs_root])
        assert_equal(["chiebukuro"],                     d[:allowed_mcp])
        assert_equal(["fs.read", "fs.write"],            d[:allowed_builtin])
        assert_equal(8,                                  d[:max_iters])
        assert_equal("You are a CRuby 4.x coding assistant.\n", d[:body])
      end
    end
  end

  def test_defaults_when_frontmatter_omits_fields
    Dir.mktmpdir do |gem_dir|
      write(File.join(gem_dir, "agents", "y.md"), <<~MD)
        ---
        name: y
        engine: scripted
        ---
        hello
      MD
      Dir.mktmpdir do |project_dir|
        d = AD.load("y", gem_agents_dir: File.join(gem_dir, "agents"),
                         project_agents_dir: File.join(project_dir, "agents"))
        assert_equal("default", d[:model])
        assert_equal(".",       d[:fs_root])
        assert_equal([],        d[:allowed_mcp])
        assert_equal([],        d[:allowed_builtin])
        assert_equal(8,         d[:max_iters])
      end
    end
  end

  def test_project_local_overrides_gem
    Dir.mktmpdir do |gem_dir|
      Dir.mktmpdir do |project_dir|
        write(File.join(gem_dir, "agents", "x.md"), <<~MD)
          ---
          name: x
          engine: scripted
          ---
          gem body
        MD
        write(File.join(project_dir, "agents", "x.md"), <<~MD)
          ---
          name: x
          engine: scripted
          ---
          project body
        MD
        d = AD.load("x", gem_agents_dir: File.join(gem_dir, "agents"),
                         project_agents_dir: File.join(project_dir, "agents"))
        assert_equal("project body\n", d[:body])
      end
    end
  end

  def test_unknown_agent_raises
    Dir.mktmpdir do |gem_dir|
      Dir.mktmpdir do |project_dir|
        assert_raise_message(/agent 'nope' not found/) do
          AD.load("nope", gem_agents_dir: File.join(gem_dir, "agents"),
                          project_agents_dir: File.join(project_dir, "agents"))
        end
      end
    end
  end

  def test_missing_engine_raises
    Dir.mktmpdir do |gem_dir|
      write(File.join(gem_dir, "agents", "bad.md"), <<~MD)
        ---
        name: bad
        ---
        body
      MD
      Dir.mktmpdir do |project_dir|
        assert_raise_message(/engine/) do
          AD.load("bad", gem_agents_dir: File.join(gem_dir, "agents"),
                         project_agents_dir: File.join(project_dir, "agents"))
        end
      end
    end
  end

  def test_list_dedupes_with_project_priority
    Dir.mktmpdir do |gem_dir|
      Dir.mktmpdir do |project_dir|
        write(File.join(gem_dir, "agents", "x.md"), "---\nname: x\nengine: scripted\n---\ngem\n")
        write(File.join(gem_dir, "agents", "y.md"), "---\nname: y\nengine: scripted\n---\ngem\n")
        write(File.join(project_dir, "agents", "x.md"), "---\nname: x\nengine: scripted\n---\nproj\n")
        write(File.join(project_dir, "agents", "z.md"), "---\nname: z\nengine: scripted\n---\nproj\n")
        names = AD.list(gem_agents_dir: File.join(gem_dir, "agents"),
                        project_agents_dir: File.join(project_dir, "agents"))
        assert_equal(%w[x y z], names)
      end
    end
  end

  def test_scripted_replies_default_is_input_placeholder
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "x.md"), <<~MD)
        ---
        name: x
        engine: scripted
        ---
        body
      MD
      agent = RbFoundationModelMacAgent::AgentDef.load(
        "x", gem_agents_dir: dir, project_agents_dir: nil,
      )
      assert_equal(["{input}"], agent[:scripted_replies])
    end
  end

  def test_scripted_replies_from_frontmatter
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "y.md"), <<~MD)
        ---
        name: y
        engine: scripted
        scripted_replies:
          - first
          - second
        ---
        body
      MD
      agent = RbFoundationModelMacAgent::AgentDef.load(
        "y", gem_agents_dir: dir, project_agents_dir: nil,
      )
      assert_equal(%w[first second], agent[:scripted_replies])
    end
  end
end
