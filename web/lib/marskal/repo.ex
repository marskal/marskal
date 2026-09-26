defmodule Marskal.Repo do
  use Ecto.Repo,
    otp_app: :marskal,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Fetches a row the user owns. An id that is not a UUID finds nothing
  instead of raising, since ids arrive from URLs and events.
  """
  def get_owned(queryable, user, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> get_by(queryable, id: id, user_id: user.id)
      :error -> nil
    end
  end
end
