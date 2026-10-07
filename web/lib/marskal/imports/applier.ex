defmodule Marskal.Imports.Applier do
  @moduledoc """
  Writes a parsed graph for the batch's user.

  Each new record is one command, created in its final state. A source id
  already imported by this user is updated by a three-way merge
  (`Marskal.Imports.Merge`): what the source changed since it was last
  imported is applied, unless the user changed that field too. An item the
  user deleted is imported again, as a new record. A tag whose name is already used under the
  same parent, by the user or by another tag in the backup, is not created
  again; its tasks get the existing tag (ADR 0005), and an import never
  updates it. The uploaded payload is dropped once the batch is applied or
  has failed.
  """

  import Ecto.Query

  alias Marskal.Changes.Change
  alias Marskal.Dates
  alias Marskal.ImportItem
  alias Marskal.Imports
  alias Marskal.Imports.OmnifocusAdapter
  alias Marskal.Imports.Merge
  alias Marskal.Imports.TodoistAdapter
  alias Marskal.ProjectFolders
  alias Marskal.ProjectFolders.ProjectFolder
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
        updated: @kinds,
        skipped: @kinds,
        kept: [],
        kept_count: 0,
        recreated: 0,
        source_tag_ids: MapSet.new(),
        existing: existing_items(batch)
      }

      acc =
        graph.tags
        |> by_level()
        |> Enum.reduce(acc, &apply_tag(batch, &1, &2))

      acc = %{acc | source_tag_ids: source_tag_ids(acc)}

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
          Map.merge(batch.stats || %{}, %{
            "created" => acc.created,
            "updated" => acc.updated,
            "skipped" => acc.skipped,
            "kept" => acc.kept_count,
            "recreated" => acc.recreated,
            "kept_samples" => acc.kept
          }),
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

  # Every tag an import from this source has mapped to.
  defp source_tag_ids(acc) do
    acc.existing
    |> Map.values()
    |> Enum.map(& &1.tag_id)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

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
    with %ImportItem{tag_id: id} = item <- Map.get(acc.existing, node.source_id),
         %Tags.Tag{} = tag <- Tags.get_tag(batch.user, id) do
      acc |> put_id(node, id) |> update_tag(batch, node, item, tag)
    else
      _ ->
        user = batch.user
        name = clip(node.name, 200)
        parent_id = live_tag_parent(user, acc, node)

        # Look first: a failed insert would abort the import's transaction.
        case Tags.find_tag(user, parent_id, name) do
          %Tags.Tag{} = existing ->
            # The user's own tag: used, never updated by an import.
            acc
            |> record!(batch, :tag, node, %{tag_id: existing.id}, nil)
            |> put_id(node, existing.id)
            |> count(:skipped, "tags")

          nil ->
            attrs = %{"name" => name, "parent_id" => parent_id, "state" => node.state}
            {:ok, tag} = Tags.create_tag(user, attrs, Ecto.UUID.generate())

            acc
            |> record!(batch, :tag, node, %{tag_id: tag.id}, Merge.snapshot(:tag, tag))
            |> put_id(node, tag.id)
            |> count(:created, "tags")
        end
    end
  end

  # A parent the user has since deleted means the tag goes to the top.
  defp live_tag_parent(user, acc, node) do
    parent_id = acc.ids[node.parent_source_id]
    if parent_id && Tags.get_tag(user, parent_id), do: parent_id
  end

  # Only a tag the import created has a base; one it reused from the user
  # is left alone. Before bases were stored, a tag the import created was
  # inserted just before its item.
  defp update_tag(acc, batch, node, item, tag) do
    base =
      cond do
        is_map(item.fields) -> item.fields
        DateTime.diff(item.inserted_at, tag.inserted_at) in 0..5 -> base_from_feed(:tag, tag.id)
        true -> nil
      end

    if base do
      incoming = %{
        "name" => clip(node.name, 200) |> String.trim() |> String.normalize(:nfc),
        "parent_id" => live_tag_parent(batch.user, acc, node),
        "state" => to_string(node.state)
      }

      {patch, kept} = Merge.fields(:tag, base, Merge.snapshot(:tag, tag), incoming)

      # A name taken by another tag would fail the whole import.
      {patch, kept} =
        if Map.has_key?(patch, "name") and
             name_taken?(
               batch.user,
               tag,
               Map.get(patch, "parent_id", tag.parent_id),
               patch["name"]
             ),
           do: {Map.delete(patch, "name"), kept ++ ["name"]},
           else: {patch, kept}

      {patch, kept} =
        applicable(
          :tag,
          patch,
          kept,
          Tags.Tag.update_changeset(tag, batch.user, patch, fn _ -> "V" end)
        )

      if patch != %{},
        do: {:ok, _} = Tags.update_tag(batch.user, tag.id, patch, Ecto.UUID.generate())

      acc
      |> store_base!(item, incoming)
      |> outcome(node.name, "tags", patch != %{}, kept)
    else
      count(acc, :skipped, "tags")
    end
  end

  defp name_taken?(user, tag, parent_id, name) do
    case Tags.find_tag(user, parent_id, name) do
      %Tags.Tag{id: id} -> id != tag.id
      nil -> false
    end
  end

  defp tag_all!(user, kind, owner_id, tag_ids) do
    Enum.filter(tag_ids, fn tag_id ->
      result =
        case kind do
          :task -> Tags.tag_task(user, owner_id, tag_id, Ecto.UUID.generate())
          :project -> Tags.tag_project(user, owner_id, tag_id, Ecto.UUID.generate())
        end

      # A tag the user deleted since an earlier import is left off.
      case result do
        {:ok, _} -> true
        {:error, :not_found} -> false
      end
    end)
  end

  defp untag_all!(user, kind, owner_id, tag_ids) do
    for tag_id <- tag_ids do
      {:ok, _} =
        case kind do
          :task -> Tags.untag_task(user, owner_id, tag_id, Ecto.UUID.generate())
          :project -> Tags.untag_project(user, owner_id, tag_id, Ecto.UUID.generate())
        end
    end
  end

  defp source_tags(node, acc),
    do: node.tag_source_ids |> Enum.map(&acc.ids[&1]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp apply_folder(batch, node, acc) do
    with %ImportItem{project_folder_id: id} = item <- Map.get(acc.existing, node.source_id),
         %ProjectFolder{} = folder <- ProjectFolders.get_folder(batch.user, id) do
      acc |> put_id(node, id) |> update_folder(batch, node, item, folder)
    else
      _ ->
        {:ok, folder} =
          ProjectFolders.create_folder(batch.user, folder_attrs(node, acc), Ecto.UUID.generate())

        acc
        |> record!(
          batch,
          :folder,
          node,
          %{project_folder_id: folder.id},
          Merge.snapshot(:folder, folder)
        )
        |> put_id(node, folder.id)
        |> count(:created, "folders")
    end
  end

  defp folder_attrs(node, acc) do
    %{
      "name" => clip(node.name, 200),
      "parent_id" => acc.ids[node.parent_source_id],
      "state" => if(node.dropped, do: "dropped", else: "active")
    }
  end

  defp update_folder(acc, batch, node, item, folder) do
    user = batch.user
    desired = folder_attrs(node, acc)
    incoming = merged(:folder, ProjectFolder.update_changeset(folder, user, desired))
    base = item.fields || base_from_feed(:folder, folder.id)

    {patch, kept} = Merge.fields(:folder, base, Merge.snapshot(:folder, folder), incoming)

    {patch, kept} =
      applicable(:folder, patch, kept, ProjectFolder.update_changeset(folder, user, patch))

    if patch != %{},
      do: {:ok, _} = ProjectFolders.update_folder(user, folder.id, patch, Ecto.UUID.generate())

    acc
    |> store_base!(item, incoming)
    |> outcome(node.name, "folders", patch != %{}, kept)
  end

  defp apply_project(batch, node, acc) do
    with %ImportItem{project_id: id} = item <- Map.get(acc.existing, node.source_id),
         %Projects.Project{} = project <- Projects.get_project(batch.user, id) do
      acc |> put_id(node, id) |> update_project(batch, node, item, project)
    else
      _ ->
        {:ok, project} =
          Projects.create_project(
            batch.user,
            project_attrs(node, acc, batch.user),
            Ecto.UUID.generate()
          )

        tags = tag_all!(batch.user, :project, project.id, source_tags(node, acc))
        base = Merge.snapshot(:project, project) |> Map.put("tag_ids", Enum.sort(tags))

        acc
        |> record!(batch, :project, node, %{project_id: project.id}, base)
        |> put_id(node, project.id)
        |> count(:created, "projects")
    end
  end

  defp project_attrs(node, acc, user) do
    %{
      "title" => clip(node.title, Tasks.Task.title_max()),
      "notes" => node.notes,
      "url" => node.url,
      "project_folder_id" => acc.ids[node.folder_source_id],
      "state" => state(node.state)
    }
    |> Map.merge(dates(node, user))
  end

  defp update_project(acc, batch, node, item, project) do
    user = batch.user
    desired = project_attrs(node, acc, user)
    incoming = merged(:project, Projects.Project.update_changeset(project, desired))
    base = item.fields || base_from_feed(:project, project.id)

    {patch, kept} = Merge.fields(:project, base, Merge.snapshot(:project, project), incoming)

    {patch, kept} =
      applicable(:project, patch, kept, Projects.Project.update_changeset(project, patch))

    if patch != %{} do
      {:ok, _} =
        Projects.update_project(user, project.id, patch, Ecto.UUID.generate(),
          at: desired["resolved_at"]
        )
    end

    current_tags = live_tag_ids(Tags.ProjectTag, :project_id, project.id)
    tags = source_tags(node, acc)
    {add, remove} = Merge.tags(base_tags(base, current_tags, acc), current_tags, tags)
    tag_all!(user, :project, project.id, add)
    untag_all!(user, :project, project.id, remove)

    acc
    |> store_base!(item, Map.put(incoming, "tag_ids", Enum.sort(tags)))
    |> outcome(node.title, "projects", patch != %{} or add != [] or remove != [], kept)
  end

  defp apply_task(batch, node, acc) do
    with %ImportItem{task_id: id} = item <- Map.get(acc.existing, node.source_id),
         %Tasks.Task{} = task <- Tasks.get_task(batch.user, id) do
      update_task(acc, batch, node, item, task)
    else
      _ ->
        {:ok, task} =
          Tasks.create_task(batch.user, task_attrs(node, acc, batch.user), Ecto.UUID.generate())

        tags = tag_all!(batch.user, :task, task.id, source_tags(node, acc))
        base = Merge.snapshot(:task, task) |> Map.put("tag_ids", Enum.sort(tags))

        acc
        |> record!(batch, :task, node, %{task_id: task.id}, base)
        |> count(:created, "tasks")
    end
  end

  # The project wins over a source inbox flag. A project the import did
  # not create leaves the task in the inbox (ADR 0017).
  defp task_attrs(node, acc, user) do
    project_id = node.project_source_id && acc.ids[node.project_source_id]

    %{
      "title" => clip(node.title, Tasks.Task.title_max()),
      "notes" => node.notes,
      "url" => node.url,
      "inbox" => is_nil(project_id),
      "project_id" => project_id,
      "state" => state(node.state)
    }
    |> Map.merge(dates(node, user))
  end

  defp update_task(acc, batch, node, item, task) do
    user = batch.user
    desired = task_attrs(node, acc, user)
    incoming = merged(:task, Tasks.Task.update_changeset(task, desired))
    base = item.fields || base_from_feed(:task, task.id)

    {patch, kept} = Merge.fields(:task, base, Merge.snapshot(:task, task), incoming)
    {patch, kept} = applicable(:task, patch, kept, Tasks.Task.update_changeset(task, patch))

    if patch != %{} do
      {:ok, _} =
        Tasks.update_task(user, task.id, patch, Ecto.UUID.generate(), at: desired["resolved_at"])
    end

    current_tags = live_tag_ids(Tags.TaskTag, :task_id, task.id)
    tags = source_tags(node, acc)
    {add, remove} = Merge.tags(base_tags(base, current_tags, acc), current_tags, tags)
    tag_all!(user, :task, task.id, add)
    untag_all!(user, :task, task.id, remove)

    acc
    |> store_base!(item, Map.put(incoming, "tag_ids", Enum.sort(tags)))
    |> outcome(node.title, "tasks", patch != %{} or add != [] or remove != [], kept)
  end

  # The fields as the changeset would store them, so they compare with
  # what is stored.
  defp merged(kind, changeset),
    do: Merge.snapshot(kind, Ecto.Changeset.apply_changes(changeset))

  # A field that would not validate, such as a folder move into its own
  # subtree, is kept as the user has it rather than failing the import.
  defp applicable(_kind, patch, kept, %Ecto.Changeset{valid?: true}), do: {patch, kept}

  defp applicable(kind, patch, kept, changeset) do
    bad = MapSet.new(changeset.errors, fn {field, _} -> Atom.to_string(field) end)

    Enum.reduce(Merge.groups(kind), {patch, kept}, fn group, {patch, kept} ->
      if Enum.any?(group, &MapSet.member?(bad, &1)) and Map.has_key?(patch, hd(group)),
        do: {Map.drop(patch, group), kept ++ [hd(group)]},
        else: {patch, kept}
    end)
  end

  # Before bases were stored: the import's insert, over the defaults it
  # left out.
  defp base_from_feed(kind, id) do
    {type, struct} =
      case kind do
        :task -> {"task", %Tasks.Task{}}
        :project -> {"project", %Projects.Project{}}
        :folder -> {"project_folder", %ProjectFolder{}}
        :tag -> {"tag", %Tags.Tag{}}
      end

    patch =
      Change
      |> where([c], c.entity_type == ^type and c.entity_id == ^id)
      |> order_by([c], asc: c.id)
      |> limit(1)
      |> select([c], c.patch)
      |> Repo.one()

    Map.merge(Merge.snapshot(kind, struct), Map.take(patch || %{}, Merge.fields(kind)))
  end

  # Without a stored base, the source's tags the item has now stand in for
  # the ones the import set.
  defp base_tags(%{"tag_ids" => ids}, _current, _acc), do: ids

  defp base_tags(_base, current, acc),
    do: Enum.filter(current, &MapSet.member?(acc.source_tag_ids, &1))

  defp live_tag_ids(schema, owner_field, owner_id) do
    schema
    |> where([l], field(l, ^owner_field) == ^owner_id and is_nil(l.discarded_at))
    |> select([l], l.tag_id)
    |> Repo.all()
  end

  defp store_base!(acc, item, fields) do
    item = item |> ImportItem.changeset(%{fields: fields}) |> Repo.update!()
    %{acc | existing: Map.put(acc.existing, item.source_id, item)}
  end

  @kept_samples 50

  defp outcome(acc, title, kind, changed?, kept) do
    acc = count(acc, if(changed?, do: :updated, else: :skipped), kind)

    if kept == [] do
      acc
    else
      sample = %{"kind" => kind, "title" => to_string(title), "fields" => kept}
      kept_list = if length(acc.kept) < @kept_samples, do: acc.kept ++ [sample], else: acc.kept
      %{acc | kept: kept_list, kept_count: acc.kept_count + 1}
    end
  end

  # Source dates are read in the user's zone when they carry none. A value
  # that does not parse is left out; the item keeps its source row. An
  # indefinite defer wins over a defer date (ADR 0006).
  defp dates(node, user) do
    zone = Marskal.Accounts.timezone(user)

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

  # An item whose record the user deleted is imported again as a new
  # record, on the same item row; the tombstone stays as it was.
  defp record!(acc, batch, kind, node, links, fields) do
    attrs =
      Map.merge(links, %{
        import_batch_id: batch.id,
        user_id: batch.user_id,
        source: batch.source,
        kind: kind,
        source_id: node.source_id,
        extras: node.extras || %{},
        fields: fields
      })

    {item, acc} =
      case Map.get(acc.existing, node.source_id) do
        %ImportItem{} = deleted ->
          {deleted |> ImportItem.changeset(attrs) |> Repo.update!(),
           %{acc | recreated: acc.recreated + 1}}

        nil ->
          {%ImportItem{} |> ImportItem.changeset(attrs) |> Repo.insert!(), acc}
      end

    %{acc | existing: Map.put(acc.existing, node.source_id, item)}
  end
end
