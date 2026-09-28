defmodule Marskal.Tags do
  @moduledoc """
  Nested tags and the links that put them on tasks and projects (ADR 0005).

  Writes go through `Marskal.Changes.apply/4`. Deleting and merging touch a
  whole subtree in one user action; each row they touch gets its own change,
  under a command id derived from the action's, so replaying the action
  replays nothing twice.
  """

  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.Projects
  alias Marskal.Rank
  alias Marskal.Repo
  alias Marskal.Tags.Link
  alias Marskal.Tags.ProjectTag
  alias Marskal.Tags.Tag
  alias Marskal.Tags.Search
  alias Marskal.Tags.TaskTag
  alias Marskal.Tags.Tree
  alias Marskal.Tasks
  alias Marskal.Tasks.Task
  alias Marskal.Uuid

  @doc "Every live tag the user has, dropped ones included, in sibling order."
  def list_tags(%User{} = user) do
    Tag
    |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at))
    |> order_by([t], asc: t.rank, asc: t.id)
    |> Repo.all()
  end

  @doc "The user's live tags as a `Marskal.Tags.Tree`."
  def tree(%User{} = user), do: Tree.new(list_tags(user))

  @doc "Autocomplete over the user's visible tags (ADR 0005)."
  def search(%Tree{} = tree, query), do: Search.run(tree, query)

  @doc """
  Each task's effective tags: its own, then its project's (ADR 0005), as
  `%{tag: tag, inherited: boolean}` in tree order, keyed by task id. Tags
  from a parent task are never included.
  """
  def effective_tags(%User{} = user, tasks, %Tree{} = tree) do
    direct = link_pairs(TaskTag, :task_id, user, Enum.map(tasks, & &1.id))

    inherited =
      link_pairs(ProjectTag, :project_id, user, tasks |> Enum.map(& &1.project_id) |> Enum.uniq())

    Map.new(tasks, fn task ->
      own = Map.get(direct, task.id, [])
      from_project = Map.get(inherited, task.project_id, []) -- own

      entries =
        for {id, inherited?} <- Enum.map(own, &{&1, false}) ++ Enum.map(from_project, &{&1, true}),
            tag = Tree.get(tree, id),
            do: %{tag: tag, inherited: inherited?}

      {task.id, Enum.sort_by(entries, &Tree.position(tree, &1.tag.id))}
    end)
  end

  @doc """
  What a task list shows about tags: `%{tags: effective, unavailable: ids}`
  for these tasks, from one tree.
  """
  def annotate(%User{} = user, tasks) do
    tree = tree(user)
    effective = effective_tags(user, tasks, tree)
    %{tags: effective, unavailable: unavailable_ids(tree, effective)}
  end

  @doc "A project's own tags, in tree order."
  def project_tags(%User{} = user, project, %Tree{} = tree) do
    ProjectTag
    |> link_pairs(:project_id, user, [project.id])
    |> Map.get(project.id, [])
    |> Enum.flat_map(&List.wrap(Tree.get(tree, &1)))
    |> Enum.sort_by(&Tree.position(tree, &1.id))
  end

  @doc "Ids of the tasks that tag state makes unavailable (ADR 0005)."
  def unavailable_ids(%Tree{} = tree, effective) do
    for {task_id, entries} <- effective,
        not Tree.available?(tree, Enum.map(entries, & &1.tag.id)),
        into: MapSet.new(),
        do: task_id
  end

  @doc "The tasks that are available, keeping their order."
  def reject_unavailable(%User{} = user, tasks) do
    tree = tree(user)
    unavailable = unavailable_ids(tree, effective_tags(user, tasks, tree))
    Enum.reject(tasks, &MapSet.member?(unavailable, &1.id))
  end

  @doc """
  The tag view (ADR 0005): the tag's own to-do tasks, then one group per
  child tag, nested the same way. Inbox tasks are included (ADR 0010). A
  task shows under every tag it carries. Empty groups are left out, and so
  are dropped subtrees, unless the selected tag is itself dropped.

  Returns `%{root: node, tree: tree, effective: map, unavailable: MapSet}`,
  where a node
  is `%{tag: tag, tasks: [task], children: [node]}`, or nil for an unknown
  tag.
  """
  def outline(%User{} = user, tag_id) do
    tree = tree(user)

    with %Tag{} = tag <- Tree.get(tree, tag_id) do
      include? =
        if Tree.visible?(tree, tag.id),
          do: &Tree.visible?(tree, &1.id),
          else: fn _tag -> true end

      ids = tree |> Tree.subtree(tag.id) |> Enum.filter(include?) |> Enum.map(& &1.id)
      tasks = to_do_tasks_tagged(user, ids)
      effective = effective_tags(user, tasks, tree)

      by_tag =
        for task <- tasks, %{tag: t} <- effective[task.id], t.id in ids, reduce: %{} do
          acc -> Map.update(acc, t.id, [task], &[task | &1])
        end
        |> Map.new(fn {id, tasks} -> {id, Enum.reverse(tasks)} end)

      %{
        root: outline_node(tree, tag, by_tag, include?),
        tree: tree,
        effective: effective,
        unavailable: unavailable_ids(tree, effective)
      }
    end
  end

  @doc "To-do tasks, inbox included, with no effective tags."
  def untagged_tasks(%User{} = user) do
    tree = tree(user)

    tasks =
      Task
      |> where([t], t.user_id == ^user.id and t.state == :to_do and is_nil(t.discarded_at))
      |> order_by([t], desc: t.inserted_at, desc: t.id)
      |> Repo.all()

    effective = effective_tags(user, tasks, tree)
    Enum.filter(tasks, &(effective[&1.id] == []))
  end

  @doc "The live tag with this name under a parent (nil for the top), ignoring case."
  def find_tag(%User{} = user, parent_id, name) do
    Tag
    |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at))
    |> where_parent(parent_id)
    |> where([t], fragment("? = ?::citext", t.name, ^String.normalize(String.trim(name), :nfc)))
    |> Repo.one()
  end

  @doc "A live tag the user owns."
  def get_tag(%User{} = user, id) do
    case Repo.get_owned(Tag, user, id) do
      %Tag{discarded_at: nil} = tag -> tag
      _ -> nil
    end
  end

  def create_tag(%User{} = user, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "tag", fn ->
      changeset = Tag.create_changeset(%Tag{}, user, attrs, &next_rank(user, &1))

      case Repo.insert(changeset) do
        {:ok, tag} -> {:ok, tag, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc "Patch any of name, parent_id, and state in one command."
  def update_tag(%User{} = user, id, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "tag", fn ->
      case get_tag(user, id) do
        nil -> {:error, :not_found}
        tag -> write_tag(user, tag, attrs)
      end
    end)
  end

  def rename_tag(user, id, name, command_id),
    do: update_tag(user, id, %{name: name}, command_id)

  def move_tag(user, id, parent_id, command_id),
    do: update_tag(user, id, %{parent_id: parent_id}, command_id)

  def set_tag_state(user, id, state, command_id),
    do: update_tag(user, id, %{state: state}, command_id)

  @doc """
  Discards the tag, its descendants, and their links. Dropping is the
  everyday way to retire a tag; deleting is for mistakes.
  """
  def delete_tag(%User{} = user, id, command_id) do
    Changes.apply(user, command_id, "tag", fn ->
      case get_tag(user, id) do
        nil -> {:error, :not_found}
        tag -> discard_subtree(user, command_id, tag)
      end
    end)
  end

  @doc """
  Folds `duplicate` into `target` (ADR 0014): links and children move to
  the target, clashing children merge in turn, and the duplicate is
  discarded with `merged_into_id` set.
  """
  def merge_tag(%User{} = user, duplicate_id, target_id, command_id) do
    Changes.apply(user, command_id, "tag", fn ->
      with %Tag{} = duplicate <- get_tag(user, duplicate_id),
           %Tag{} = target <- get_tag(user, target_id),
           :ok <- validate_merge(duplicate, target) do
        merge(user, command_id, duplicate, target)
      else
        nil -> {:error, :not_found}
        {:error, _} = error -> error
      end
    end)
  end

  def tag_task(user, task_id, tag_id, command_id),
    do: write_link(user, :task, task_id, tag_id, :tag, command_id)

  def untag_task(user, task_id, tag_id, command_id),
    do: write_link(user, :task, task_id, tag_id, :untag, command_id)

  def tag_project(user, project_id, tag_id, command_id),
    do: write_link(user, :project, project_id, tag_id, :tag, command_id)

  def untag_project(user, project_id, tag_id, command_id),
    do: write_link(user, :project, project_id, tag_id, :untag, command_id)

  ## Reading

  defp link_pairs(schema, owner_field, user, owner_ids) do
    owner_ids = Enum.reject(owner_ids, &is_nil/1)

    schema
    |> where([l], l.user_id == ^user.id and is_nil(l.discarded_at))
    |> where([l], field(l, ^owner_field) in ^owner_ids)
    |> order_by([l], asc: l.inserted_at, asc: l.id)
    |> select([l], {field(l, ^owner_field), l.tag_id})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp to_do_tasks_tagged(user, tag_ids) do
    tagged =
      from l in TaskTag,
        where: l.user_id == ^user.id and l.tag_id in ^tag_ids and is_nil(l.discarded_at),
        select: l.task_id

    via_project =
      from l in ProjectTag,
        where: l.user_id == ^user.id and l.tag_id in ^tag_ids and is_nil(l.discarded_at),
        select: l.project_id

    Task
    |> where([t], t.user_id == ^user.id and t.state == :to_do and is_nil(t.discarded_at))
    |> where([t], t.id in subquery(tagged) or t.project_id in subquery(via_project))
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> Repo.all()
  end

  defp outline_node(tree, tag, by_tag, include?) do
    children =
      tree
      |> Tree.children(tag.id)
      |> Enum.filter(include?)
      |> Enum.map(&outline_node(tree, &1, by_tag, include?))
      |> Enum.reject(&(&1.tasks == [] and &1.children == []))

    %{tag: tag, tasks: Map.get(by_tag, tag.id, []), children: children}
  end

  ## Tags

  defp write_tag(user, tag, attrs) do
    changeset = Tag.update_changeset(tag, user, attrs, &next_rank(user, &1))

    case Repo.update(changeset) do
      {:ok, updated} ->
        if Ecto.Changeset.changed?(changeset, :name) or
             Ecto.Changeset.changed?(changeset, :parent_id) do
          refresh_descendants!(updated)
        end

        {:ok, updated, changeset}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp next_rank(user, parent_id) do
    Tag
    |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at))
    |> where_parent(parent_id)
    |> select([t], max(t.rank))
    |> Repo.one()
    |> Rank.between(nil)
  end

  defp where_parent(query, nil), do: where(query, [t], is_nil(t.parent_id))
  defp where_parent(query, parent_id), do: where(query, [t], t.parent_id == ^parent_id)

  defp live_children(tag) do
    Tag
    |> where([t], t.parent_id == ^tag.id and is_nil(t.discarded_at))
    |> order_by([t], asc: t.rank, asc: t.id)
    |> Repo.all()
  end

  # parent_path is derived and not synced (ADR 0014), so descendants are
  # rewritten here without a change row.
  defp refresh_descendants!(%Tag{} = tag) do
    path = Tag.path(tag)

    Tag
    |> where([t], t.parent_id == ^tag.id)
    |> Repo.all()
    |> Enum.each(fn child ->
      child
      |> Ecto.Changeset.change(%{parent_path: path})
      |> Repo.update!()
      |> refresh_descendants!()
    end)
  end

  defp discard_subtree(user, command_id, tag) do
    for child <- live_children(tag) do
      cascade(user, command_id, "tag", child.id, fn ->
        discard_subtree(user, command_id, child)
      end)
    end

    for {schema, type} <- [{TaskTag, "task_tag"}, {ProjectTag, "project_tag"}],
        link <- live_links(schema, tag) do
      cascade(user, command_id, type, link.id, fn -> discard_link(link) end)
    end

    discard(tag)
  end

  defp discard(tag, merged_into_id \\ nil) do
    changeset = Tag.discard_changeset(tag, merged_into_id)
    {:ok, Repo.update!(changeset), changeset}
  end

  defp validate_merge(%Tag{id: id}, %Tag{id: id}), do: {:error, :same_tag}

  # Merging a tag into its own descendant would move the target under itself.
  defp validate_merge(duplicate, target) do
    if duplicate.id in ancestor_ids(target), do: {:error, :into_descendant}, else: :ok
  end

  defp ancestor_ids(%Tag{parent_id: nil}), do: []
  defp ancestor_ids(%Tag{parent_id: id}), do: [id | ancestor_ids(Repo.get!(Tag, id))]

  defp merge(user, command_id, duplicate, target) do
    for {schema, kind} <- [{TaskTag, :task}, {ProjectTag, :project}],
        link <- live_links(schema, duplicate) do
      owner_id = Map.fetch!(link, owner_field(kind))

      cascade(user, command_id, "#{kind}_tag", Link.id(kind, owner_id, target.id), fn ->
        upsert_link(user, kind, owner_id, target, :tag)
      end)

      cascade(user, command_id, "#{kind}_tag", link.id, fn -> discard_link(link) end)
    end

    for child <- live_children(duplicate) do
      case twin(target, child.name) do
        nil ->
          cascade(user, command_id, "tag", child.id, fn ->
            write_tag(user, child, %{parent_id: target.id})
          end)

        twin ->
          cascade(user, command_id, "tag", child.id, fn ->
            merge(user, command_id, child, twin)
          end)
      end
    end

    discard(duplicate, target.id)
  end

  # Names are citext; comparing through a text parameter would be
  # case-sensitive, so cast it.
  defp twin(parent, name) do
    Tag
    |> where([t], t.parent_id == ^parent.id and is_nil(t.discarded_at))
    |> where([t], fragment("? = ?::citext", t.name, ^name))
    |> Repo.one()
  end

  # A cascaded write gets its own command id, derived from the action's.
  defp cascade(user, command_id, type, entity_id, fun) do
    {:ok, _} = Changes.apply(user, Uuid.v5(command_id, "#{type}|#{entity_id}"), type, fun)
  end

  ## Links

  defp write_link(user, kind, owner_id, tag_id, action, command_id) do
    Changes.apply(user, command_id, "#{kind}_tag", fn ->
      with %{} = owner <- get_owner(user, kind, owner_id),
           %Tag{} = tag <- resolve_tag(user, tag_id) do
        upsert_link(user, kind, owner.id, tag, action)
      else
        nil -> {:error, :not_found}
      end
    end)
  end

  defp get_owner(user, :task, id), do: Tasks.get_task(user, id)
  defp get_owner(user, :project, id), do: Projects.get_project(user, id)

  # A tag folded into another stands for the one it went into (ADR 0014).
  defp resolve_tag(user, id) do
    case Repo.get_owned(Tag, user, id) do
      %Tag{discarded_at: nil} = tag -> tag
      %Tag{merged_into_id: into} when not is_nil(into) -> resolve_tag(user, into)
      _ -> nil
    end
  end

  defp upsert_link(user, kind, owner_id, tag, action) do
    schema = link_schema(kind)
    id = Link.id(kind, owner_id, tag.id)

    case {Repo.get(schema, id), action} do
      {nil, :tag} ->
        changeset =
          Ecto.Changeset.change(struct(schema, id: id), [
            {:user_id, user.id},
            {owner_field(kind), owner_id},
            {:tag_id, tag.id}
          ])

        {:ok, Repo.insert!(changeset), changeset}

      {nil, :untag} ->
        {:error, :not_found}

      {link, :tag} ->
        changeset = Ecto.Changeset.change(link, discarded_at: nil)
        {:ok, Repo.update!(changeset), changeset}

      {%{discarded_at: nil} = link, :untag} ->
        discard_link(link)

      {link, :untag} ->
        {:ok, link, Ecto.Changeset.change(link)}
    end
  end

  defp discard_link(link) do
    changeset = Ecto.Changeset.change(link, discarded_at: DateTime.utc_now(:second))
    {:ok, Repo.update!(changeset), changeset}
  end

  defp live_links(schema, tag) do
    schema
    |> where([l], l.tag_id == ^tag.id and is_nil(l.discarded_at))
    |> Repo.all()
  end

  defp link_schema(:task), do: TaskTag
  defp link_schema(:project), do: ProjectTag

  defp owner_field(:task), do: :task_id
  defp owner_field(:project), do: :project_id
end
