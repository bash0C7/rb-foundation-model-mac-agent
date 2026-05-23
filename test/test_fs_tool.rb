# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class TestFsTool < Test::Unit::TestCase
  def setup
    @tmp = Dir.mktmpdir
    @root = File.realpath(@tmp)
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def test_read_returns_file_content
    path = File.join(@root, "a.txt")
    File.write(path, "hello\n")
    assert_equal("hello\n", RbFoundationModelMacAgent::FsTool.read(path: path, fs_root: @root))
  end

  def test_write_creates_file_and_parent_dirs
    path = File.join(@root, "sub", "dir", "b.txt")
    result = RbFoundationModelMacAgent::FsTool.write(path: path, content: "x", fs_root: @root)
    assert_true(File.exist?(path))
    assert_equal("x", File.read(path))
    assert_match(/wrote 1 bytes/, result)
  end

  def test_relative_path_resolves_under_fs_root
    path_rel = "a.txt"
    File.write(File.join(@root, "a.txt"), "hello\n")
    assert_equal("hello\n",
                 RbFoundationModelMacAgent::FsTool.read(path: path_rel, fs_root: @root))
  end

  def test_relative_path_with_dotslash_resolves_under_fs_root
    File.write(File.join(@root, "b.txt"), "world\n")
    assert_equal("world\n",
                 RbFoundationModelMacAgent::FsTool.read(path: "./b.txt", fs_root: @root))
  end

  def test_path_outside_root_rejected
    other = Dir.mktmpdir
    begin
      escape = File.join(other, "secret.txt")
      File.write(escape, "nope")
      assert_raise_message(/path outside fs_root/) do
        RbFoundationModelMacAgent::FsTool.read(path: escape, fs_root: @root)
      end
    ensure
      FileUtils.rm_rf(other)
    end
  end

  def test_symlink_escape_blocked
    other_dir = Dir.mktmpdir
    begin
      target = File.join(other_dir, "secret.txt")
      File.write(target, "nope")
      link = File.join(@root, "link.txt")
      File.symlink(target, link)
      assert_raise_message(/path outside fs_root/) do
        RbFoundationModelMacAgent::FsTool.read(path: link, fs_root: @root)
      end
    ensure
      FileUtils.rm_rf(other_dir)
    end
  end

  def test_dotdot_escape_blocked
    nested = File.join(@root, "nested")
    FileUtils.mkdir_p(nested)
    escape = File.join(nested, "..", "..", "etc", "passwd")
    assert_raise_message(/path outside fs_root/) do
      RbFoundationModelMacAgent::FsTool.read(path: escape, fs_root: @root)
    end
  end
end
