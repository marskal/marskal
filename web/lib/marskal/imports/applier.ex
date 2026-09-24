defmodule Marskal.Imports.Applier do
  @moduledoc false

  import Ecto.Query

  alias Marskal.ImportItem
  alias Marskal.Imports.OmnifocusAdapter
  alias Marskal.ProjectFolders
  alias Marskal.Projects
  alias Marskal.Repo
  alias Marskal.Tasks

  def call(batch) do
    batch = Repo.preload(batch, :user)

    try do
      apply_graph(batch)
    rescue
      error ->
        {:error, mark_failed(batch, error)}
    end
  end

  defp apply_graph(batch) do
    graph = OmnifocusAdapter.parse(batch.payload, filename: batch.filename)
    created = %{"folders" => 0, "projects" => 0, "tasks" => 0}
    skipped = %{"folders" => 0, "projects" => 0, "tasks" => 0}

    Repo.transaction(fn ->
      existing = existing_items(batch)

      {folder_ids, created, skipped, existing} =
        apply_folders(batch, graph.folders, created, skipped, existing)

      {project_ids, created, skipped, existing} =
        apply_projects(batch, graph.projects, folder_ids, created, skipped, existing)

      {created, skipped, _existing} =
        apply_tasks(batch, graph.tasks, project_ids, created, skipped, existing)

      batch
      |> Ecto.Changeset.change(%{
        status: :applied,
        stats: Map.merge(batch.stats || %{}, %{"created" => created, "skipped" => skipped}),
        error_message: nil
      })
      |> Repo.update!()
    end)
  end

  defp mark_failed(batch, error) do
    message = "Import failed: #{Exception.message(error)}" |> String.slice(0, 1000)

    batch
    |> Ecto.Changeset.change(%{status: :failed, error_message: message})
    |> Repo.update!()
  end

  defp existing_items(batch) do
    ImportItem
    |> where([i], i.user_id == ^batch.user_id and i.source == ^batch.source)
    |> Repo.all()
    |> Map.new(&{&1.source_id, &1})
  end

  defp apply_folders(batch, folders, created, skipped, existing) do
    remaining = Map.new(folders, &{&1.source_id, &1})
    place(batch, remaining, %{}, created, skipped, existing, map_size(remaining) + 1)
  end

  defp place(batch, remaining, ids, created, skipped, existing, 0) do
    Enum.reduce(remaining, {ids, created, skipped, existing}, fn {_sid, node},
                                                                 {ids, created, skipped, existing} ->
      {id, created, skipped, existing} =
        upsert_folder(batch, node, ids, created, skipped, existing)

      {Map.put(ids, node.source_id, id), created, skipped, existing}
    end)
  end

  defp place(batch, remaining, ids, created, skipped, existing, guard) do
    if remaining == %{} do
      {ids, created, skipped, existing}
    else
      {remaining, ids, created, skipped, existing, progressed} =
        Enum.reduce(remaining, {remaining, ids, created, skipped, existing, false}, fn {sid, node},
                                                                                       {remaining,
                                                                                        ids,
                                                                                        created,
                                                                                        skipped,
                                                                                        existing,
                                                                                        progressed} ->
          waiting =
            is_binary(node.parent_source_id) and
              not Map.has_key?(ids, node.parent_source_id) and
              Map.has_key?(remaining, node.parent_source_id)

          if waiting do
            {remaining, ids, created, skipped, existing, progressed}
          else
            {id, created, skipped, existing} =
              upsert_folder(batch, node, ids, created, skipped, existing)

            {Map.delete(remaining, sid), Map.put(ids, sid, id), created, skipped, existing, true}
          end
        end)

      if progressed do
        place(batch, remaining, ids, created, skipped, existing, guard - 1)
      else
        place(batch, remaining, ids, created, skipped, existing, 0)
      end
    end
  end

  defp upsert_folder(batch, node, folder_ids, created, skipped, existing) do
    case Map.get(existing, node.source_id) do
      %ImportItem{} = item ->
        {item.project_folder_id, created, Map.update!(skipped, "folders", &(&1 + 1)), existing}

      nil ->
        user = batch.user

        {:ok, folder} =
          ProjectFolders.create_folder(
            user,
            %{"name" => clip(node.name, 200), "parent_id" => folder_ids[node.parent_source_id]},
            Ecto.UUID.generate()
          )

        folder =
          if node.dropped do
            {:ok, folder} = ProjectFolders.drop_folder(user, folder.id, Ecto.UUID.generate())
            folder
          else
            folder
          end

        existing =
          record!(
            batch,
            :folder,
            node.source_id,
            node.extras,
            %{project_folder_id: folder.id},
            existing
          )

        {folder.id, Map.update!(created, "folders", &(&1 + 1)), skipped, existing}
    end
  end

  defp apply_projects(batch, projects, folder_ids, created, skipped, existing) do
    Enum.reduce(projects, {%{}, created, skipped, existing}, fn node,
                                                                {ids, created, skipped, existing} ->
      case Map.get(existing, node.source_id) do
        %ImportItem{project_id: project_id} = item ->
          if is_binary(node.notes) and node.notes != "" and item.project_id do
            Projects.set_notes(batch.user, project_id, node.notes, Ecto.UUID.generate())
          end

          {Map.put(ids, node.source_id, project_id), created,
           Map.update!(skipped, "projects", &(&1 + 1)), existing}

        nil ->
          {:ok, project} =
            Projects.create_project(
              batch.user,
              %{
                "title" => clip(node.title, 200),
                "notes" => node.notes,
                "project_folder_id" => folder_ids[node.folder_source_id]
              },
              Ecto.UUID.generate()
            )

          project = set_state(project, node.state, batch.user, :project)

          existing =
            record!(
              batch,
              :project,
              node.source_id,
              node.extras,
              %{project_id: project.id},
              existing
            )

          {Map.put(ids, node.source_id, project.id), Map.update!(created, "projects", &(&1 + 1)),
           skipped, existing}
      end
    end)
  end

  defp apply_tasks(batch, tasks, project_ids, created, skipped, existing) do
    Enum.reduce(tasks, {created, skipped, existing}, fn node, {created, skipped, existing} ->
      case Map.get(existing, node.source_id) do
        %ImportItem{task_id: task_id} ->
          if is_binary(node.notes) and node.notes != "" and task_id do
            Tasks.set_notes(batch.user, task_id, node.notes, Ecto.UUID.generate())
          end

          {created, Map.update!(skipped, "tasks", &(&1 + 1)), existing}

        nil ->
          inbox = node.inbox or is_nil(node.project_source_id)

          {:ok, task} =
            Tasks.create_task(
              batch.user,
              %{
                "title" => clip(node.title, 500),
                "notes" => node.notes,
                "inbox" => inbox,
                "project_id" => if(inbox, do: nil, else: project_ids[node.project_source_id])
              },
              Ecto.UUID.generate()
            )

          _task = set_state(task, node.state, batch.user, :task)

          existing =
            record!(batch, :task, node.source_id, node.extras, %{task_id: task.id}, existing)

          {Map.update!(created, "tasks", &(&1 + 1)), skipped, existing}
      end
    end)
  end

  defp clip(nil, _max), do: "Untitled"

  defp clip(text, max) do
    case text |> to_string() |> String.trim() |> String.slice(0, max) do
      "" -> "Untitled"
      clipped -> clipped
    end
  end

  defp set_state(record, "done", user, :project) do
    {:ok, project} = Projects.complete_project(user, record.id, Ecto.UUID.generate())
    project
  end

  defp set_state(record, "dropped", user, :project) do
    {:ok, project} = Projects.drop_project(user, record.id, Ecto.UUID.generate())
    project
  end

  defp set_state(record, "done", user, :task) do
    {:ok, task} = Tasks.complete_task(user, record.id, Ecto.UUID.generate())
    task
  end

  defp set_state(record, "dropped", user, :task) do
    {:ok, task} = Tasks.drop_task(user, record.id, Ecto.UUID.generate())
    task
  end

  defp set_state(record, _state, _user, _kind), do: record

  defp record!(batch, kind, source_id, extras, links, existing) do
    item =
      %ImportItem{}
      |> ImportItem.changeset(
        Map.merge(links, %{
          import_batch_id: batch.id,
          user_id: batch.user_id,
          source: batch.source,
          kind: kind,
          source_id: source_id,
          extras: extras || %{}
        })
      )
      |> Repo.insert!()

    Map.put(existing, source_id, item)
  end
end
