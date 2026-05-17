# frozen_string_literal: true

require "json"
require "fileutils"

# File-backed cache for FIDO Metadata Service blobs.
# Persists the MDS table of contents to disk so it survives process restarts
# and deploys. Falls back to in-memory only if the cache directory is not writable.
class FidoCacheStore
  def initialize(dir: "tmp/cache/fido_metadata")
    @memory = {}
    @dir = begin
      FileUtils.mkdir_p(dir)
      dir
    rescue Errno::EROFS, Errno::EACCES => e
      APP_LOGGER.info { "[FidoCacheStore] #{dir} not writable (#{e.class}); using memory-only cache" }
      nil
    end
  end

  def read(name, _options = nil)
    return @memory[name] if @memory.key?(name)
    return nil unless @dir

    path = cache_path(name)
    return nil unless File.exist?(path)

    data = Marshal.load(File.binread(path)) # rubocop:disable Security/MarshalLoad
    @memory[name] = data
    data
  rescue StandardError
    nil
  end

  def write(name, value, **_options)
    @memory[name] = value
    return unless @dir

    File.binwrite(cache_path(name), Marshal.dump(value))
  rescue StandardError => e
    APP_LOGGER.debug { "[FidoCacheStore] Failed to write cache file for #{name}: #{e.message}" }
  end

  def delete(name, _options = nil)
    @memory.delete(name)
    return unless @dir

    FileUtils.rm_f(cache_path(name))
  rescue StandardError
    nil
  end

  def clear(_options = nil)
    @memory.clear
    return unless @dir

    FileUtils.rm_rf(@dir)
    FileUtils.mkdir_p(@dir)
  rescue StandardError
    nil
  end

  private

  def cache_path(name)
    safe_name = name.gsub(/[^a-zA-Z0-9_-]/, "_")
    File.join(@dir, "#{safe_name}.bin")
  end
end
