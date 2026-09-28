defmodule Marskal.Imports.Applier do
  @moduledoc """
  Writes a parsed graph for the batch's user.

  Each new record is one command, created in its final state. A source id
  already imported by this user is skipped and left as the user has it now,
  tags included: only new tasks and projects are tagged. A tag whose name is
  already used under the same parent, by the user or by another tag in the
  backup, is not created again; its tasks get the existing tag (ADR 0005).
  The uploaded payload is dropped once the batch is applied or has failed.
  """

  import Ecto.Query

  alias Marskal.Dates
  alias Marskal.ImportItem
  alias Marskal.Imports
  alias Marskal.Imports.OmnifocusAdapter
  alias Marskal.Imports.TodoistAdapter
  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Repo
  alias Marskal.Tags
  alias Marskal.Tasks

  @kinds %{"folders" => 0, "projects" => 0, "tasks" => 0, "tags" => 0}

  def call(batch) do
    batch = batch |> Repo.preload(:user) |> Imports.load_payload()

    try do
      with {:ok, applied} <- apply_graph(batch) do
        Marskal.Changes.broadcast(batch.user, "import_batch", batch.id)
        {:ok, applied}
      end
    rescue
      error ->
        {:error, mark_failed(batch, error)}
    end
  end

  defp apply_graph(batch) do
    graph = graph_for(batch)

    Repo.transaction(fn ->
      acc = %{
        ids: %{},
        created: @kinds,
        skipped: @kinds,
        existing: existing_items(batch)
      }

      acc =
        graph.tags
        |> by_level()
        |> Enum.reduce(acc, &apply_tag(batch, &1, &2))

      acc =
        graph.folders
        |> parents_first()
        |> Enum.reduce(acc, &apply_folder(batch, &1, &2))

      acc = Enum.reduce(graph.projects, acc, &apply_project(batch, &1, &2))
      acc = Enum.reduce(graph.tasks, acc, &apply_task(batch, &1, &2))

      batch
      |> Ecto.Changeset.change(%{
        status: :applied,
        stats:
          Map.merge(batch.stats || %{}, %{"created" => acc.created, "skipped" => acc.skipped}),
        error_message: nil
      })
      |> Ecto.Changeset.force_change(:payload, nil)
      |> Repo.update!()
    end)
  end

  defp mark_failed(batch, error) do
    message = "Import failed: #{Exception.message(error)}" |> String.slice(0, 1000)

    batch
    |> Ecto.Changeset.change(%{status: :failed, error_message: message})
    |> Ecto.Changeset.force_change(:payload, nil)
    |> Repo.update!()
  end

  defp graph_for(%{source: "todoist"} = batch), do: TodoistAdapter.parse(batch.payload)

  defp graph_for(batch), do: OmnifocusAdapter.parse(batch.payload, filename: batch.filename)

  defp existing_items(batch) do
    ImportItem
    |> where([i], i.user_id == ^batch.user_id and i.source == ^batch.source)
    |> Repo.all()
    |> Map.new(&{&1.source_id, &1})
  end

  # Depth-first on the parent link, so a parent is created before its
  # children. A parent cycle in the source is cut where it closes.
  defp parents_first(folders) do
    by_id = Map.new(folders, &{&1.source_id, &1})

    {ordered, _seen} =
      Enum.reduce(folders, {[], MapSet.new()}, &visit(&1, by_id, &2, MapSet.new()))

    Enum.reverse(ordered)
  end

  # Level by level, siblings in source rank order, so every parent is
  # created before its children and new tags keep the source's order.
  defp by_level(tags) do
    {levels, _} =
      tags
      |> parents_first()
      |> Enum.map_reduce(%{}, fn node, depths ->
        depth = if d = depths[node.parent_source_id], do: d + 1, else: 0
        {{depth, node}, Map.put(depths, node.source_id, depth)}
      end)

    levels
    |> Enum.sort_by(fn {depth, node} -> {depth, node.rank} end)
    |> Enum.map(&elem(&1, 1))
  end

  defp visit(node, by_id, {ordered, seen} = acc, path) do
    if MapSet.member?(seen, node.source_id) or MapSet.member?(path, node.source_id) do
      acc
    else
      {ordered, seen} =
        case Map.get(by_id, node.parent_source_id) do
          nil -> {ordered, seen}
          parent -> visit(parent, by_id, {ordered, seen}, MapSet.put(path, node.source_id))
        end

      {[node | ordered], MapSet.put(seen, node.source_id)}
    end
  end

  defp apply_tag(batch, node, acc) do
    case Map.get(acc.existing, node.source_id) do
      %ImportItem{tag_id: id} ->
        acc |> put_id(node, id) |> count(:skipped, "tags")

      nil ->
        user = batch.user
        name = clip(node.name, 200)
        # A parent the user has since deleted means the tag goes to the top.
        parent_id = acc.ids[node.parent_source_id]
        parent_id = if parent_id && Tags.get_tag(user, parent_id), do: parent_id

        # Look first: a failed insert would abort the import's transaction.
        {tag, bucket} =
          case Tags.find_tag(user, parent_id, name) do
            %Tags.Tag{} = existing ->
              {existing, :skipped}

            nil ->
              attrs = %{"name" => name, "parent_id" => parent_id, "state" => node.state}
              {:ok, tag} = Tags.create_tag(user, attrs, Ecto.UUID.generate())
              {tag, :created}
          end

        acc
        |> record!(batch, :tag, node, %{tag_id: tag.id})
        |> put_id(node, tag.id)
        |> count(bucket, "tags")
    end
  end

  defp tag_all!(user, kind, owner_id, node, acc) do
    for source_id <- node.tag_source_ids, tag_id = acc.ids[source_id], reduce: :ok do
      :ok ->
        result =
          case kind do
            :task -> Tags.tag_task(user, owner_id, tag_id, Ecto.UUID.generate())
            :project -> Tags.tag_project(user, owner_id, tag_id, Ecto.UUID.generate())
          end

        # A tag the user deleted since an earlier import is left off.
        case result do
          {:ok, _} -> :ok
          {:error, :not_found} -> :ok
        end
    end
  end

  defp apply_folder(batch, node, acc) do
    case Map.get(acc.existing, node.source_id) do
      %ImportItem{project_folder_id: id} ->
        acc |> put_id(node, id) |> count(:skipped, "folders")

      nil ->
        {:ok, folder} =
          ProjectFolders.create_folder(
            batch.user,
            %{
              "name" => clip(node.name, 200),
              "parent_id" => acc.ids[node.parent_source_id],
              "state" => if(node.dropped, do: "dropped", else: "active")
            },
            Ecto.UUID.generate()
          )

        acc
        |> record!(batch, :folder, node, %{project_folder_id: folder.id})
        |> put_id(node, folder.id)
        |> count(:created, "folders")
    end
  end

  defp apply_project(batch, node, acc) do
    case Map.get(acc.existing, node.source_id) do
      %ImportItem{project_id: id} ->
        acc |> put_id(node, id) |> count(:skipped, "projects")

      nil ->
        {:ok, project} =
          Projects.create_project(
            batch.user,
            %{
              "title" => clip(node.title, Tasks.Task.title_max()),
              "notes" => node.notes,
              "project_folder_id" => acc.ids[node.folder_source_id],
              "state" => state(node.state)
            }
            |> Map.merge(dates(node, batch.user)),
            Ecto.UUID.generate()
          )

        tag_all!(batch.user, :project, project.id, node, acc)

        acc
        |> record!(batch, :project, node, %{project_id: project.id})
        |> put_id(node, project.id)
        |> count(:created, "projects")
    end
  end

  defp apply_task(batch, node, acc) do
    case Map.get(acc.existing, node.source_id) do
      %ImportItem{} ->
        count(acc, :skipped, "tasks")

      nil ->
        # The project wins over a source inbox flag. A project the import
        # did not create leaves the task in the inbox (ADR 0017).
        project_id = node.project_source_id && acc.ids[node.project_source_id]

        {:ok, task} =
          Tasks.create_task(
            batch.user,
            %{
              "title" => clip(node.title, Tasks.Task.title_max()),
              "notes" => node.notes,
              "inbox" => is_nil(project_id),
              "project_id" => project_id,
              "state" => state(node.state)
            }
            |> Map.merge(dates(node, batch.user)),
            Ecto.UUID.generate()
          )

        tag_all!(batch.user, :task, task.id, node, acc)

        acc
        |> record!(batch, :task, node, %{task_id: task.id})
        |> count(:created, "tasks")
    end
  end

  # Source dates are read in the user's zone when they carry none. A value
  # that does not parse is left out; the item keeps its source row. An
  # indefinite defer wins over a defer date (ADR 0006).
  defp dates(node, user) do
    zone = user.timezone

    %{
      "deferred_indefinitely" => node.deferred_indefinitely == true,
      "defer_until" =>
        if(node.deferred_indefinitely, do: nil, else: parse(node.defer_until, :defer_until, zone)),
      "planned_at" => parse(node.planned, :planned_at, zone),
      "due_at" => parse(node.due, :due_at, zone),
      "resolved_at" =>
        if(state(node.state) != "to_do", do: parse(node.resolved_at, :resolved_at, zone))
    }
  end

  defp parse(value, field, zone), do: Dates.parse_source(value, field, zone)

  defp state(state) when state in ["done", "dropped"], do: state
  defp state(_state), do: "to_do"

  defp put_id(acc, node, id), do: %{acc | ids: Map.put(acc.ids, node.source_id, id)}

  defp count(acc, bucket, kind) do
    Map.update!(acc, bucket, &Map.update!(&1, kind, fn n -> n + 1 end))
  end

  defp clip(nil, _max), do: "Untitled"

  defp clip(text, max) do
    case text |> to_string() |> String.trim() |> String.slice(0, max) do
      "" -> "Untitled"
      clipped -> clipped
    end
  end

  defp record!(acc, batch, kind, node, links) do
    item =
      %ImportItem{}
      |> ImportItem.changeset(
        Map.merge(links, %{
          import_batch_id: batch.id,
          user_id: batch.user_id,
          source: batch.source,
          kind: kind,
          source_id: node.source_id,
          extras: node.extras || %{}
        })
      )
      |> Repo.insert!()

    %{acc | existing: Map.put(acc.existing, node.source_id, item)}
  end
end
