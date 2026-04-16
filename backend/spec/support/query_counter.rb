# frozen_string_literal: true

# Counts SELECT queries issued against DB while the given block runs. Uses a
# plain Logger whose writes are captured — this is simpler than stubbing Sequel
# internals and works with Sequel's existing :sql log level.
class QueryCounter
  def self.count(&block)
    new.count(&block)
  end

  def initialize
    @queries = []
  end

  def count
    prev_loggers = DB.loggers.dup
    DB.loggers << CaptureLogger.new(@queries)
    begin
      yield
    ensure
      DB.loggers.replace(prev_loggers)
    end
    # Sequel logs every query as one info line. Count only SELECT statements
    # (ignoring BEGIN/COMMIT wrappers emitted by DatabaseCleaner).
    @queries.count { |q| q.to_s =~ /SELECT\b/i }
  end

  # Minimal logger the Sequel adapter can call. Only :info carries the SQL
  # body; other levels are ignored.
  class CaptureLogger
    def initialize(sink)
      @sink = sink
    end

    def info(msg)
      @sink << msg
    end

    def warn(_msg); end
    def error(_msg); end
    def debug(_msg); end
  end
end
