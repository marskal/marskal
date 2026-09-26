defmodule Marskal.Imports.ApplyJob do
  @moduledoc false

  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [
      period: 60,
      fields: [:worker, :args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Marskal.ImportBatch
  alias Marskal.Imports.Applier
  alias Marskal.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"batch_id" => batch_id}}) do
    case Repo.get(ImportBatch, batch_id) do
      %ImportBatch{status: :applying} = batch ->
        _result = Applier.call(batch)
        :ok

      _batch ->
        :ok
    end
  end
end
