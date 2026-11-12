# Postgres intervals decode to Elixir's `Duration`, as the review interval
# is read (ADR 0026).
Postgrex.Types.define(
  Marskal.PostgresTypes,
  Ecto.Adapters.Postgres.extensions(),
  interval_decode_type: Duration
)
