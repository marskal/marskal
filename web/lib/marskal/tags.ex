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
  alias Marskal.Tags.TaskTag
  alias Marskal.Tasks
  alias Marskal.Uuid

  @doc "Every live tag the user has, dropped ones included, in sibling order."
  def list_tags(%User{} = user) do
    Tag
    |> where([t], t.user_id == ^user.id and is_nil(t.discarded_at))
    |> order_by([t], asc: t.rank, asc: t.id)
    |> Repo.all()
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
