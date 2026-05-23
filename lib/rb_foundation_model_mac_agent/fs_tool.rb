# frozen_string_literal: true

require "fileutils"
require "pathname"

module RbFoundationModelMacAgent
  module FsTool
    module_function

    def read(path:, fs_root:)
      abs = ensure_inside(path, fs_root)
      File.read(abs)
    end

    def write(path:, content:, fs_root:)
      abs = ensure_inside_for_write(path, fs_root)
      FileUtils.mkdir_p(File.dirname(abs))
      File.write(abs, content)
      "wrote #{content.bytesize} bytes to #{abs}"
    end

    # path may be relative or absolute and must resolve (after symlink expansion)
    # inside fs_root. Resolves via nearest-existing-parent so containment check
    # fires before hitting ENOENT for non-existent escape targets like ../../etc/passwd.
    def ensure_inside(path, fs_root)
      root        = File.realpath(File.expand_path(fs_root))
      target      = File.expand_path(path, root)
      parent      = nearest_existing_parent(target)
      parent_real = File.realpath(parent)
      relative    = Pathname.new(target).relative_path_from(Pathname.new(parent)).to_s
      resolved    = File.expand_path(relative, parent_real)
      raise "path outside fs_root: #{resolved}" unless inside?(resolved, root)
      # If target itself exists, resolve symlinks fully (catches symlink escape
      # where the link sits inside root but points outside).
      if File.exist?(resolved) || File.symlink?(resolved)
        abs = File.realpath(resolved)
        raise "path outside fs_root: #{abs}" unless inside?(abs, root)
        abs
      else
        resolved
      end
    end

    # For write, the file may not exist yet — resolve via the nearest existing
    # parent directory so we still get realpath-based escape detection.
    def ensure_inside_for_write(path, fs_root)
      root   = File.realpath(File.expand_path(fs_root))
      target = File.expand_path(path, root)
      parent = nearest_existing_parent(target)
      parent_real = File.realpath(parent)
      relative   = Pathname.new(target).relative_path_from(Pathname.new(parent)).to_s
      resolved   = File.expand_path(relative, parent_real)
      raise "path outside fs_root: #{resolved}" unless inside?(resolved, root)
      resolved
    end

    def inside?(abs, root)
      abs == root || abs.start_with?(root + File::SEPARATOR)
    end

    def nearest_existing_parent(path)
      cur = File.dirname(path)
      cur = File.dirname(cur) until File.exist?(cur) || cur == "/" || cur == "."
      cur
    end
  end
end
