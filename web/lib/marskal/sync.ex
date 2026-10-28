defmodule Marskal.Sync do
  @moduledoc """
  The pull side of the sync API (ADR 0014, ADR 0019).

  A pull without a cursor is a snapshot: every live row the user can see,
  and the cursor of the latest change, read together. A pull with a cursor
  returns the current row of each entity changed after it, tombstones
  included. Rows carry synced fields only; derived ones, such as
  `parent_path`, are left out.
  """

  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.Changes.Change
  alias Marskal.Repo

  @page 1000

  @entities [
    {"user_preferences", Marskal.Accounts.UserPreferences,
     ~w(id timezone week_start locale home_view keymap default_review_interval inserted_at
        updated_at)a},
    {"recurrence_series", Marskal.Recurrence.Series,
     ~w(id kind mode anchor interval frequency weekdays on_days
        ends_at end_count week_start stopped_at discarded_at inserted_at updated_at)a},
    {"task", Marskal.Tasks.Task,
     ~w(id title notes url flagged state inbox project_id parent_id rank defer_until deferred_indefinitely
        planned_at due_at series_id occurrence_for resolved_at discarded_at inserted_at
        updated_at)a},
    {"project", Marskal.Projects.Project,
     ~w(id title notes url flagged state project_folder_id rank defer_until deferred_indefinitely planned_at
        due_at series_id occurrence_for review_interval next_review_on last_reviewed_at
        resolved_at discarded_at inserted_at updated_at)a},
    {"project_folder", Marskal.ProjectFolders.ProjectFolder,
     ~w(id name parent_id state rank discarded_at inserted_at updated_at)a},
    {"tag", Marskal.Tags.Tag,
     ~w(id name parent_id state rank merged_into_id discarded_at inserted_at updated_at)a},
    {"task_tag", Marskal.Tags.TaskTag,
     ~w(id task_id tag_id discarded_at inserted_at updated_at)a},
    {"project_tag", Marskal.Tags.ProjectTag,
     ~w(id project_id tag_id discarded_at inserted_at updated_at)a}
  ]

  @doc "The entity types that sync, in the order a client should apply them."
  def entity_types, do: Enum.map(@entities, &elem(&1, 0))

  @doc "The most changes one incremental pull covers."
  def page_size, do: @page

  @doc """
  A snapshot (`cursor` nil) or the changes after `cursor`. `limit` is for
  tests.
  """
  def pull(user, cursor, limit \\ @page)

  # The cursor is read before the rows. Every change up to it has committed
  # (`Marskal.Changes` allocates ids in commit order per user), so the rows
  # are at least that new. A row newer than the cursor comes again on the
  # next pull, which is harmless.
  def pull(%User{} = user, nil, _limit) do
    cursor =
      Change
      |> where([c], c.user_id == ^user.id)
      |> select([c], max(c.id))
      |> Repo.one()

    rows =
      Map.new(@entities, fn {type, schema, fields} ->
        {type,
         schema
         |> where([r], r.user_id == ^user.id)
         |> live()
         |> order_by([r], asc: r.id)
         |> Repo.all()
         |> Enum.map(&encode(&1, fields))}
      end)

    response(user, cursor || 0, true, false, rows)
  end

  def pull(%User{} = user, cursor, limit) when is_integer(cursor) and cursor >= 0 do
    changes =
      Change
      |> where([c], c.user_id == ^user.id and c.id > ^cursor)
      |> order_by([c], asc: c.id)
      |> limit(^(limit + 1))
      |> select([c], {c.id, c.entity_type, c.entity_id})
      |> Repo.all()

    {page, more} =
      if length(changes) > limit,
        do: {Enum.take(changes, limit), true},
        else: {changes, false}

    next_cursor =
      case List.last(page) do
        nil -> cursor
        {id, _type, _entity_id} -> id
      end

    ids_by_type =
      Enum.group_by(page, &elem(&1, 1), &elem(&1, 2))
      |> Map.new(fn {type, ids} -> {type, Enum.uniq(ids)} end)

    rows =
      Map.new(@entities, fn {type, schema, fields} ->
        ids = Map.get(ids_by_type, type, [])

        {type,
         if ids == [] do
           []
         else
           schema
           |> where([r], r.user_id == ^user.id and r.id in ^ids)
           |> order_by([r], asc: r.id)
           |> Repo.all()
           |> Enum.map(&encode(&1, fields))
         end}
      end)

    response(user, next_cursor, false, more, rows)
  end

  # Visibility is the owner until sharing, so nothing is ever gone yet
  # (ADR 0019). The user's timezone is also in the preferences row; it
  # stays here for clients from before that row (ADR 0023).
  defp response(user, cursor, snapshot, more, rows) do
    %{
      cursor: cursor,
      snapshot: snapshot,
      more: more,
      user: %{id: user.id, timezone: Marskal.Accounts.timezone(user)},
      rows: rows,
      gone: []
    }
  end

  # A row without discarded_at, such as the preferences, lives as long as
  # its user.
  defp live(query) do
    %{from: %{source: {_table, schema}}} = query

    if :discarded_at in schema.__schema__(:fields),
      do: where(query, [r], is_nil(r.discarded_at)),
      else: query
  end

  defp encode(record, fields) do
    Map.new(fields, fn field ->
      {Atom.to_string(field), Changes.encode_value(Map.fetch!(record, field))}
    end)
  end
end
