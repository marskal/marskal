defmodule Marskal.Repo do
  use Ecto.Repo,
    otp_app: :marskal,
    adapter: Ecto.Adapters.Postgres
end
