# frozen_string_literal: true

require "fileutils"
require "pathname"

module RbFoundationModelMacAgent
  module FsTool
    module_function

    def read(path:, fs_root:)
      File.read(ensure_inside(path, fs_root))
    end

    def write(path:, content:, fs_root:)
      abs = ensure_inside(path, fs_root)
      FileUtils.mkdir_p(File.dirname(abs))
      File.write(abs, content)
      "wrote #{content.bytesize} bytes to #{abs}"
    end

    def ensure_inside(path, fs_root)
      root        = File.realpath(File.expand_path(fs_root))
      target      = File.expand_path(path, root)
      parent      = nearest_existing_parent(target)
      relative    = Pathname.new(target).relative_path_from(Pathname.new(parent)).to_s
      resolved    = File.expand_path(relative, File.realpath(parent))
      raise "path outside fs_root: #{resolved}" unless inside?(resolved, root)
      return resolved unless File.symlink?(resolved) || File.exist?(resolved)
      abs = File.realpath(resolved)
      raise "path outside fs_root: #{abs}" unless inside?(abs, root)
      abs
    end

    def inside?(abs, root)
      abs == root || abs.start_with?(root + File::SEPARATOR)
    end

    def nearest_existing_parent(path)
      cur = File.dirname(path)
      cur = File.dirname(cur) until File.exist?(cur) || cur == "/"
      cur
    end
  end
end
