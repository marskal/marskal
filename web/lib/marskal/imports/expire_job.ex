defmodule Marskal.Imports.ExpireJob do
  @moduledoc """
  Drops the payload of uploads that were never applied.

  A batch that sits pending or previewed longer than `@max_age_hours` is
  marked expired and its backup is cleared. Runs hourly from Oban's cron.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  import Ecto.Query
  alias Marskal.ImportBatch
  alias Marskal.Repo

  @max_age_hours 24

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {_count, _} = expire(DateTime.utc_now(:second))
    :ok
  end

  def expire(now) do
    cutoff = DateTime.add(now, -@max_age_hours, :hour)

    ImportBatch
    |> where([b], b.status in [:pending, :previewed] and b.updated_at < ^cutoff)
    |> Repo.update_all(
      set: [
        status: :expired,
        payload: nil,
        error_message: "This upload expired before it was imported. Upload the backup again.",
        updated_at: now
      ]
    )
  end
end
