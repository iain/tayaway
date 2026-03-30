# typed: true

module FidoMetadata
  class TestCacheStore
    def initialize; end
    def read(name, options = nil); end
    def write(name, value, options = nil); end
    def delete(name, options = nil); end
    def clear(options = nil); end
  end
end
