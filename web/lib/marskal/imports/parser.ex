defmodule Marskal.Imports.Parser do
  @moduledoc false

  alias Marskal.Imports.OmnifocusAdapter
  alias Marskal.Imports.TaskpaperAdapter
  alias Marskal.Imports.TodoistAdapter
  alias Marskal.Repo

  def call(batch) do
    batch = Marskal.Imports.load_payload(batch)

    cond do
      batch.source == "todoist" ->
        read(batch, fn -> TodoistAdapter.parse(batch.payload) end)

      OmnifocusAdapter.match?(batch.payload, batch.filename) ->
        read(batch, fn -> OmnifocusAdapter.parse(batch.payload, filename: batch.filename) end)

      TaskpaperAdapter.match?(batch.payload, batch.filename) or batch.source == "taskpaper" ->
        read(%{batch | source: "taskpaper"}, fn -> TaskpaperAdapter.parse(batch.payload) end)

      true ->
        fail!(batch, unsupported(batch))
    end
  rescue
    error in ArgumentError ->
      fail!(batch, error.message)

    # reach:disable-next-line bare_rescue -- an unreadable file of any kind fails the batch
    error ->
      fail!(batch, unreadable(batch, error))
  end

  # Rescue here so this batch, including a source chosen above, is the one
  # the failure is written on. Bindings from `call/1` stay the stored row.
  defp read(batch, parse) do
    preview(batch, parse.())
  rescue
    error in ArgumentError ->
      fail!(batch, error.message)

    # reach:disable-next-line bare_rescue -- an unreadable file of any kind fails the batch
    error ->
      fail!(batch, unreadable(batch, error))
  end

  defp unsupported(%{source: "taskpaper"}) do
    "This file is not a TaskPaper outline. A task starts with a dash, and a project ends with a colon."
  end

  defp unsupported(_batch) do
    "This file is not a supported import. Upload a TaskPaper file, or an OmniFocus Backup Document (.ofocus-backup)."
  end

  defp unreadable(%{source: "taskpaper"}, error),
    do: "Could not read this outline (#{error.__struct__})."

  defp unreadable(_batch, error), do: "Could not read this backup (#{error.__struct__})."

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
    |> Ecto.Changeset.change(%{status: :failed, error_message: message, source: batch.source})
    # The payload may not be loaded, so force the clear.
    |> Ecto.Changeset.force_change(:payload, nil)
    |> Repo.update!()
  end
end
