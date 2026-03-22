# typed: strict
# frozen_string_literal: true

class Sequel::Migrator
  sig { params(db: Sequel::Database, directory: String, target: T.nilable(Integer)).returns(T.untyped) }
  def self.run(db, directory, target: nil); end
end

class Sequel::IntegerMigrator
  sig { params(db: Sequel::Database, directory: String, opts: T.untyped).void }
  def initialize(db, directory, **opts); end

  sig { returns(Integer) }
  def current; end
end
