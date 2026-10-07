defmodule Marskal.Changes do
  @moduledoc """
  The command write path and the change feed (ADR 0014).

  `apply/4` runs a write once per command id and appends its patch to the
  feed. A write that changes nothing appends nothing. Each accepted change is
  broadcast to the owner's LiveViews after the transaction commits. Inside a
  caller's transaction nothing is broadcast, since the caller may still roll
  back; that caller broadcasts once with `broadcast/3` after its commit.
  """

  alias Marskal.Changes.Change
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects.Project
  alias Marskal.Recurrence.Series
  alias Marskal.Repo
  alias Marskal.Tags.ProjectTag
  alias Marskal.Tags.Tag
  alias Marskal.Tags.TaskTag
  alias Marskal.Tasks.Task

  def subscribe(user) do
    Phoenix.PubSub.subscribe(Marskal.PubSub, topic(user.id))
  end

  def apply(user, command_id, entity_type, fun) when is_function(fun, 0) do
    with :ok <- validate_command_id(command_id) do
      nested? = Repo.in_transaction?()

      Repo.transaction(fn ->
        # Two requests with the same command id wait here, so the second one
        # sees the first one's change row and replays it.
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [command_id])

        take_or_insert(user, command_id, entity_type, fun)
      end)
      |> publish(user, entity_type, nested?)
    end
  end

  @doc """
  A write that follows from another command, such as a subtree moving with
  its root. It gets its own command id, derived from the action's, so a
  replay of the action replays it too.
  """
  def cascade(user, command_id, entity_type, entity_id, fun) do
    {:ok, _} =
      __MODULE__.apply(
        user,
        Marskal.Uuid.v5(command_id, "#{entity_type}|#{entity_id}"),
        entity_type,
        fun
      )
  end

  def encode_patch(%Ecto.Changeset{} = changeset) do
    Map.new(changeset.changes, fn {key, value} ->
      {Atom.to_string(key), encode_value(value)}
    end)
  end

  def broadcast(user, entity_type, id) do
    Phoenix.PubSub.broadcast(Marskal.PubSub, topic(user.id), {:marskal_change, entity_type, id})
  end

  @doc """
  Saves a changeset in the shape `apply/4` expects.

  When the name or parent changed, `refresh` is called with the saved
  record so a tree can rebuild the rows under it.
  """
  def commit(changeset), do: commit(changeset, fn _record -> :ok end)

  def commit(changeset, refresh) when is_function(refresh, 1) do
    case Repo.update(changeset) do
      {:ok, record} ->
        if name_or_parent_changed?(changeset), do: refresh.(record)
        {:ok, record, changeset}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp topic(user_id), do: "changes:user:#{user_id}"

  defp take_or_insert(user, command_id, entity_type, fun) do
    case Repo.get_by(Change, command_id: command_id) do
      %Change{} = change -> {replay(user, change), false}
      nil -> insert_change(user, command_id, entity_type, fun.())
    end
  end

  defp insert_change(_user, _command_id, _entity_type, {:error, reason}) do
    Repo.rollback(reason)
  end

  defp insert_change(user, command_id, entity_type, {:ok, %{id: id} = entity, changeset}) do
    case encode_patch(changeset) do
      patch when patch == %{} ->
        {entity, false}

      patch ->
        # Change ids are allocated one writer at a time per user, so
        # they commit in id order and a pull cursor never passes
        # one still in flight (ADR 0019).
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
          "changes:" <> user.id
        ])

        %Change{}
        |> Change.record_changeset(%{
          command_id: command_id,
          user_id: user.id,
          entity_type: entity_type,
          entity_id: id,
          patch: patch
        })
        |> Repo.insert!()

        {entity, true}
    end
  end

  defp publish({:ok, {entity, changed?}}, user, entity_type, nested?) do
    if changed? and not nested?, do: broadcast(user, entity_type, entity.id)
    {:ok, entity}
  end

  defp publish({:error, reason}, _user, _entity_type, _nested?), do: {:error, reason}

  defp name_or_parent_changed?(changeset) do
    field_changed?(changeset, :name) or field_changed?(changeset, :parent_id)
  end

  defp field_changed?(changeset, field) do
    Map.has_key?(changeset.types, field) and Ecto.Changeset.changed?(changeset, field)
  end

  defp replay(user, %Change{entity_type: type, entity_id: id}) do
    case fetch(user, type, id) do
      nil -> Repo.rollback(:not_found)
      entity -> entity
    end
  end

  defp fetch(user, "user_preferences", id),
    do: Repo.get_by(Marskal.Accounts.UserPreferences, id: id, user_id: user.id)

  defp fetch(user, "task", id), do: Repo.get_by(Task, id: id, user_id: user.id)
  defp fetch(user, "project", id), do: Repo.get_by(Project, id: id, user_id: user.id)
  defp fetch(user, "project_folder", id), do: Repo.get_by(ProjectFolder, id: id, user_id: user.id)
  defp fetch(user, "recurrence_series", id), do: Repo.get_by(Series, id: id, user_id: user.id)
  defp fetch(user, "tag", id), do: Repo.get_by(Tag, id: id, user_id: user.id)
  defp fetch(user, "task_tag", id), do: Repo.get_by(TaskTag, id: id, user_id: user.id)
  defp fetch(user, "project_tag", id), do: Repo.get_by(ProjectTag, id: id, user_id: user.id)
  defp fetch(_user, _type, _id), do: nil

  defp validate_command_id(command_id) do
    case Ecto.UUID.cast(command_id) do
      {:ok, _} -> :ok
      :error -> {:error, :invalid_command}
    end
  end

  @doc "A field value as JSON carries it: ISO 8601 for instants, strings for enums."
  def encode_value(nil), do: nil
  def encode_value(value) when is_boolean(value), do: value
  def encode_value(value) when is_atom(value), do: Atom.to_string(value)
  def encode_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def encode_value(value), do: value
end
