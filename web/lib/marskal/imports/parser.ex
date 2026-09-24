defmodule Marskal.Imports.Parser do
  @moduledoc false

  alias Marskal.Imports.OmnifocusAdapter
  alias Marskal.Repo

  def call(batch) do
    if OmnifocusAdapter.match?(batch.payload, batch.filename) do
      graph = OmnifocusAdapter.parse(batch.payload, filename: batch.filename)

      batch
      |> Ecto.Changeset.change(%{
        source: graph.source,
        status: :previewed,
        stats: Marskal.Imports.Graph.stats(graph),
        error_message: nil
      })
      |> Repo.update!()
    else
      fail!(
        batch,
        "This file is not a supported backup. Export an OmniFocus Backup Document (.ofocus-backup)."
      )
    end
  rescue
    error in ArgumentError ->
      fail!(batch, error.message)

    error ->
      fail!(batch, "Could not read this backup (#{error.__struct__}).")
  end

  defp fail!(batch, message) do
    batch
    |> Ecto.Changeset.change(%{status: :failed, error_message: message})
    |> Repo.update!()
  end
end
