# frozen_string_literal: true

# Domain tables use UUIDv7 primary keys (ADR 0011).
#
# Rails still emits identity/`bigserial` for `:primary_key` and
# `gen_random_uuid()` (v4) when `id: :uuid` has no default. Override both so
# omitted-id INSERTs get a time-ordered UUID.
#
# A DEFAULT, not GENERATED ALWAYS: explicit ids have to keep working. Fixtures
# assign their own, companion apps mint offline, and so does `pg_restore`.

module PostgreSQLUuidV7PrimaryKeys
  def primary_key(name, type = :primary_key, **options)
    if type == :uuid
      options[:default] = options.fetch(:default) { -> { "uuidv7()" } }
    end
    super
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) do
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::NATIVE_DATABASE_TYPES[:primary_key] =
    "uuid PRIMARY KEY DEFAULT uuidv7()"

  ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.prepend(PostgreSQLUuidV7PrimaryKeys)
end
