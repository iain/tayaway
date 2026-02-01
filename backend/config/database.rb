require "sequel"

DB = Sequel.connect(ENV.fetch("DATABASE_URL"))

DB.extension :pg_json
DB.extension :pg_array

Sequel::Model.plugin :json_serializer
