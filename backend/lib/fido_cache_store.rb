# typed: true
# frozen_string_literal: true

require "json"
require "fileutils"

# File-backed cache for FIDO Metadata Service blobs.
# Persists the MDS table of contents to disk so it survives process restarts
# and deploys. Falls back to in-memory only if the cache directory is not writable.
class FidoCacheStore
  extend T::Sig

  sig { params(dir: String).void }
  def initialize(dir: "tmp/cache/fido_metadata")
    @dir = T.let(dir, String)
    @memory = T.let({}, T::Hash[String, T.untyped])
    FileUtils.mkdir_p(@dir)
  end

  sig { params(name: String, _options: T.untyped).returns(T.untyped) }
  def read(name, _options = nil)
    return @memory[name] if @memory.key?(name)

    path = cache_path(name)
    return nil unless File.exist?(path)

    data = Marshal.load(File.binread(path)) # rubocop:disable Security/MarshalLoad
    @memory[name] = data
    data
  rescue StandardError
    nil
  end

  sig { params(name: String, value: T.untyped, _options: T.untyped).void }
  def write(name, value, **_options)
    @memory[name] = value
    File.binwrite(cache_path(name), Marshal.dump(value))
  rescue StandardError => e
    APP_LOGGER.debug { "[FidoCacheStore] Failed to write cache file for #{name}: #{e.message}" }
  end

  sig { params(name: String, _options: T.untyped).void }
  def delete(name, _options = nil)
    @memory.delete(name)
    path = cache_path(name)
    FileUtils.rm_f(path)
  rescue StandardError
    nil
  end

  sig { params(_options: T.untyped).void }
  def clear(_options = nil)
    @memory.clear
    FileUtils.rm_rf(@dir)
    FileUtils.mkdir_p(@dir)
  rescue StandardError
    nil
  end

  private

  sig { params(name: String).returns(String) }
  def cache_path(name)
    safe_name = name.gsub(/[^a-zA-Z0-9_-]/, "_")
    File.join(@dir, "#{safe_name}.bin")
  end
end
