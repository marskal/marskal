defmodule Marskal.Imports.Parser do
  @moduledoc false

  alias Marskal.Imports.OmnifocusAdapter
  alias Marskal.Imports.TodoistAdapter
  alias Marskal.Repo

  def call(batch) do
    batch = Marskal.Imports.load_payload(batch)

    cond do
      batch.source == "todoist" ->
        preview(batch, TodoistAdapter.parse(batch.payload))

      OmnifocusAdapter.match?(batch.payload, batch.filename) ->
        preview(batch, OmnifocusAdapter.parse(batch.payload, filename: batch.filename))

      true ->
        fail!(
          batch,
          "This file is not a supported backup. Export an OmniFocus Backup Document (.ofocus-backup)."
        )
    end
  rescue
    error in ArgumentError ->
      fail!(batch, error.message)

    # reach:disable-next-line bare_rescue -- an unreadable backup of any kind fails the batch
    error ->
      fail!(batch, "Could not read this backup (#{error.__struct__}).")
  end

  defp preview(batch, graph) do
    batch
    |> Ecto.Changeset.change(%{
      source: graph.source,
      status: :previewed,
      stats: Marskal.Imports.Graph.stats(graph),
      error_message: nil
    })
    |> Repo.update!()
  end

  defp fail!(batch, message) do
    batch
    |> Ecto.Changeset.change(%{status: :failed, error_message: message})
    # The payload may not be loaded, so force the clear.
    |> Ecto.Changeset.force_change(:payload, nil)
    |> Repo.update!()
  end
end
