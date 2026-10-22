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
  alias Marskal.Tags.Search
  alias Marskal.Tags.Tag
  alias Marskal.Tags.TaskTag
  alias Marskal.Tags.Tree
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

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
  The tag view (ADR 0005): the tag's own tasks, then one group per child
  tag, nested the same way. Inbox tasks are included (ADR 0010). A task
  shows under every tag it carries. Empty groups are left out.

  `show:` is as in `Marskal.Tasks.list_open/2` for the tasks. Dropped tag
  subtrees stay hidden unless the selected tag is itself hidden, or
  `:dropped` is in `show`.

  Returns `%{root: node, tree: tree, effective: map, unavailable: MapSet}`,
  where a node
  is `%{tag: tag, tasks: [task], children: [node]}`, or nil for an unknown
  tag.
  """
  def outline(%User{} = user, tag_id, opts \\ []) do
    show = Keyword.get(opts, :show, [])
    tree = tree(user)

    with %Tag{} = tag <- Tree.get(tree, tag_id) do
      include? = include_fun(tree, tag, show)
      ids = tree |> Tree.subtree(tag.id) |> Enum.filter(include?) |> Enum.map(& &1.id)
      tasks = shown_tasks_tagged(user, ids, show)
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

  @doc """
  Tasks with no effective tags. `show:` is as in `Marskal.Tasks.list_open/2`;
  the default is the open ones, inbox included.
  """
  def untagged_tasks(%User{} = user, opts \\ []) do
    show = Keyword.get(opts, :show, [])
    tree = tree(user)

    tasks =
      Task
      |> Tasks.where_shown(user, show)
      |> order_by([t], desc: t.inserted_at, desc: t.id)
      |> Repo.all()
      |> then(&Tasks.without_deferred(user, &1, show))

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

  @doc """
  A client's tag insert (ADR 0014). A name already used under the same
  parent is not an error: the new tag is stored discarded, merged into the
  one already there. A merged parent stands for the tag it went into.
  """
  def insert_client_tag(%User{} = user, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "tag", fn ->
      changeset =
        Tag.create_changeset(%Tag{}, user, resolve_parent(user, attrs), &next_rank(user, &1))

      changeset =
        case clash(user, changeset, nil) do
          nil ->
            changeset

          twin ->
            Ecto.Changeset.change(changeset,
              discarded_at: DateTime.utc_now(:second),
              merged_into_id: twin.id
            )
        end

      case Repo.insert(changeset) do
        {:ok, tag} -> {:ok, tag, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc """
  A client's tag patch. A rename or move onto a name already used there
  merges this tag into that one (ADR 0014).
  """
  def patch_client_tag(%User{} = user, id, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "tag", fn ->
      case get_tag(user, id) do
        %Tag{} = tag -> patch_or_merge(user, command_id, tag, attrs)
        _ -> {:error, :not_found}
      end
    end)
  end

  defp patch_or_merge(user, command_id, tag, attrs) do
    attrs = resolve_parent(user, attrs)
    changeset = Tag.update_changeset(tag, user, attrs, &next_rank(user, &1))

    case clash(user, changeset, tag.id) do
      nil -> write_tag(user, tag, attrs)
      twin -> merge_if_valid(user, command_id, tag, twin)
    end
  end

  defp merge_if_valid(user, command_id, tag, twin) do
    with :ok <- validate_merge(tag, twin), do: merge(user, command_id, tag, twin)
  end

  defp resolve_parent(user, attrs) do
    case Map.fetch(attrs, "parent_id") do
      {:ok, id} when is_binary(id) ->
        case resolve_tag(user, id) do
          %Tag{id: resolved} -> Map.put(attrs, "parent_id", resolved)
          nil -> attrs
        end

      _ ->
        attrs
    end
  end

  # The live tag, other than `self_id`, that this changeset's name and
  # parent would collide with.
  defp clash(_user, %Ecto.Changeset{valid?: false}, _self_id), do: nil

  defp clash(user, changeset, self_id) do
    name = Ecto.Changeset.get_field(changeset, :name)

    case find_tag(user, Ecto.Changeset.get_field(changeset, :parent_id), name) do
      %Tag{id: ^self_id} -> nil
      twin -> twin
    end
  end

  def rename_tag(user, id, name, command_id),
    do: update_tag(user, id, %{name: name}, command_id)

  def move_tag(user, id, parent_id, command_id),
    do: update_tag(user, id, %{parent_id: parent_id}, command_id)

  @doc """
  Puts a tag under `parent_id` (`nil` for the top), right after the
  sibling `after_id` (`nil` for first, `:last` for last). Its children come
  along. A name already used there refuses the move.
  """
  def place_tag(%User{} = user, id, parent_id, after_id, command_id) do
    Changes.apply(user, command_id, "tag", fn ->
      with %Tag{} = tag <- get_tag(user, id) || {:error, :not_found},
           {:ok, rank} <- rank_after(user, parent_id, after_id, tag.id) do
        write_tag(user, tag, %{parent_id: parent_id, rank: rank})
      end
    end)
  end

  @doc """
  Makes the tag the last child of the sibling above it. The keyboard moves
  work on the tags the sidebar shows. `show:` in `opts` is that visibility;
  without it a dropped tag is not a neighbor.
  """
  def indent_tag(%User{} = user, id, command_id, opts \\ []) do
    with {:ok, tag, {above, _below}} <- shown_neighbors(user, id, opts) do
      if above,
        do: place_tag(user, tag.id, above.id, :last, command_id),
        else: {:error, :first}
    end
  end

  @doc "Moves the tag out of its parent, to just after it."
  def outdent_tag(%User{} = user, id, command_id) do
    case get_tag(user, id) do
      nil ->
        {:error, :not_found}

      %Tag{parent_id: nil} ->
        {:error, :top_level}

      tag ->
        place_tag(user, tag.id, get_tag(user, tag.parent_id).parent_id, tag.parent_id, command_id)
    end
  end

  @doc "Swaps the tag with the shown sibling above it."
  def move_tag_up(%User{} = user, id, command_id, opts \\ []) do
    with {:ok, tag, {above, _below}} <- shown_neighbors(user, id, opts) do
      case above && shown_neighbors(user, above.id, opts) do
        nil ->
          {:error, :first}

        {:ok, _above, {before, _}} ->
          place_tag(user, tag.id, tag.parent_id, before && before.id, command_id)
      end
    end
  end

  @doc "Swaps the tag with the shown sibling below it."
  def move_tag_down(%User{} = user, id, command_id, opts \\ []) do
    with {:ok, tag, {_above, below}} <- shown_neighbors(user, id, opts) do
      if below,
        do: place_tag(user, tag.id, tag.parent_id, below.id, command_id),
        else: {:error, :last}
    end
  end

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

  @doc """
  A new task in No project carrying this tag, both or neither. The link's
  command id derives from the task's, so a replay replays both.
  """
  def create_tagged_task(%User{} = user, tag_id, attrs, command_id) do
    attrs = Map.merge(attrs, %{"inbox" => false, "project_id" => nil})

    Repo.transact(fn ->
      with {:ok, task} <- Tasks.create_task(user, attrs, command_id),
           {:ok, _link} <-
             tag_task(user, task.id, tag_id, Marskal.Uuid.v5(command_id, "tag|#{tag_id}")) do
        {:ok, task}
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

  defp shown_tasks_tagged(user, tag_ids, show) do
    tagged =
      from l in TaskTag,
        where: l.user_id == ^user.id and l.tag_id in ^tag_ids and is_nil(l.discarded_at),
        select: l.task_id

    via_project =
      from l in ProjectTag,
        where: l.user_id == ^user.id and l.tag_id in ^tag_ids and is_nil(l.discarded_at),
        select: l.project_id

    Task
    |> Tasks.where_shown(user, show)
    |> where([t], t.id in subquery(tagged) or t.project_id in subquery(via_project))
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> Repo.all()
    |> then(&Tasks.without_deferred(user, &1, show))
  end

  @doc "Whether a tag is shown for `show`. On hold stays shown; dropped needs `:dropped`."
  def shown?(%Tree{} = tree, id, show) when is_list(show) do
    case Tree.state(tree, id) do
      nil -> false
      :dropped -> :dropped in show
      _state -> true
    end
  end

  defp include_fun(tree, tag, show) do
    if shown?(tree, tag.id, show),
      do: &shown?(tree, &1.id, show),
      else: fn _tag -> true end
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
    tag
    |> Tag.update_changeset(user, attrs, &next_rank(user, &1))
    |> Changes.commit(&refresh_descendants!/1)
  end

  defp next_rank(user, parent_id) do
    Tag
    |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at))
    |> where_parent(parent_id)
    |> select([t], max(t.rank))
    |> Repo.one()
    |> Rank.between(nil)
  end

  # The rank right after sibling `after_id`, first for `nil`, last for
  # `:last`, leaving out the tag being placed.
  defp rank_after(user, parent_id, after_id, except) do
    siblings =
      Tag
      |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at) and t.id != ^except)
      |> where_parent(parent_id)
      |> order_by([t], asc: t.rank, asc: t.id)
      |> select([t], %{id: t.id, rank: t.rank})
      |> Repo.all()

    case after_id do
      nil ->
        {:ok, Rank.between(nil, Enum.at(siblings, 0)[:rank])}

      :last ->
        {:ok, Rank.between(List.last(siblings)[:rank], nil)}

      id ->
        case Enum.find(siblings, &(&1.id == id)) do
          nil ->
            {:error, :not_a_sibling}

          %{rank: rank} ->
            next = Enum.find(siblings, &(&1.rank > rank))
            {:ok, Rank.between(rank, next && next.rank)}
        end
    end
  end

  # The tag, and the siblings just above and below it among those shown.
  # A hidden tag, on a dropped tag's own page, goes by all its siblings.
  defp shown_neighbors(user, id, opts) do
    show = Keyword.get(opts, :show, [])
    tree = tree(user)

    case Tree.get(tree, id) do
      nil ->
        {:error, :not_found}

      tag ->
        siblings =
          tree
          |> Tree.children(tag.parent_id)
          |> Enum.filter(&(shown?(tree, &1.id, show) or not shown?(tree, tag.id, show)))

        index = Enum.find_index(siblings, &(&1.id == tag.id))
        above = if index > 0, do: Enum.at(siblings, index - 1)
        {:ok, tag, {above, Enum.at(siblings, index + 1)}}
    end
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
      Changes.cascade(user, command_id, "tag", child.id, fn ->
        discard_subtree(user, command_id, child)
      end)
    end

    for {schema, type} <- [{TaskTag, "task_tag"}, {ProjectTag, "project_tag"}],
        link <- live_links(schema, tag) do
      Changes.cascade(user, command_id, type, link.id, fn -> discard_link(link) end)
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

      Changes.cascade(user, command_id, "#{kind}_tag", Link.id(kind, owner_id, target.id), fn ->
        upsert_link(user, kind, owner_id, target, :tag)
      end)

      Changes.cascade(user, command_id, "#{kind}_tag", link.id, fn -> discard_link(link) end)
    end

    for child <- live_children(duplicate) do
      merge_child(user, command_id, target, child)
    end

    discard(duplicate, target.id)
  end

  defp merge_child(user, command_id, target, child) do
    case twin(target, child.name) do
      nil ->
        Changes.cascade(user, command_id, "tag", child.id, fn ->
          write_tag(user, child, %{parent_id: target.id})
        end)

      twin ->
        Changes.cascade(user, command_id, "tag", child.id, fn ->
          merge(user, command_id, child, twin)
        end)
    end
  end

  # Names are citext; comparing through a text parameter would be
  # case-sensitive, so cast it.
  defp twin(parent, name) do
    Tag
    |> where([t], t.parent_id == ^parent.id and is_nil(t.discarded_at))
    |> where([t], fragment("? = ?::citext", t.name, ^name))
    |> Repo.one()
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
