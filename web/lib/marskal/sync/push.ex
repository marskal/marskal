defmodule Marskal.Sync.Push do
  @moduledoc """
  The push side of the sync API (ADR 0019).

  Commands apply in order, each through its context and so through
  `Marskal.Changes.apply/4`. Each gets a result: `applied`, `noop`,
  `replayed`, or `rejected` with a reason. A failure that is not about the
  command's content, such as a lost database connection, stops the push;
  the commands after it get no result, and the client sends them again.
  """

  require Logger

  import Ecto.Query
  alias Marskal.Accounts
  alias Marskal.Accounts.UserPreferences
  alias Marskal.Accounts.User
  alias Marskal.Changes.Change
  alias Marskal.ProjectFolders
  alias Marskal.ProjectFolders.ProjectFolder
  alias Marskal.Projects
  alias Marskal.Projects.Project
  alias Marskal.Recurrence
  alias Marskal.Recurrence.Series
  alias Marskal.Repo
  alias Marskal.Tags
  alias Marskal.Tags.Link
  alias Marskal.Tags.ProjectTag
  alias Marskal.Tags.Tag
  alias Marskal.Tags.TaskTag
  alias Marskal.Tasks
  alias Marskal.Tasks.Task

  @max_commands 1000

  @schemas %{
    "user_preferences" => UserPreferences,
    "task" => Task,
    "project" => Project,
    "project_folder" => ProjectFolder,
    "recurrence_series" => Series,
    "tag" => Tag,
    "task_tag" => TaskTag,
    "project_tag" => ProjectTag
  }

  def max_commands, do: @max_commands

  @doc "Applies `commands` in order. Returns one result per command handled."
  def push(%User{} = user, commands) when is_list(commands) do
    commands
    |> Enum.reduce_while([], fn command, results ->
      case run(user, command) do
        {:ok, result} -> {:cont, [result | results]}
        :stop -> {:halt, results}
      end
    end)
    |> Enum.reverse()
  end

  defp run(user, command) do
    {:ok, apply_one(user, command)}
  rescue
    _error in Ecto.ConstraintError ->
      {:ok, rejected(command, "invalid", %{})}

    error in Postgrex.Error ->
      if content_error?(error),
        do: {:ok, rejected(command, "invalid", %{})},
        else: stop(command, error, __STACKTRACE__)

    error ->
      stop(command, error, __STACKTRACE__)
  end

  # Integrity violations (class 23) and errors raised by our own triggers
  # are about what the command asked for.
  defp content_error?(%Postgrex.Error{postgres: %{code: :raise_exception}}), do: true

  defp content_error?(%Postgrex.Error{postgres: %{pg_code: "23" <> _}}), do: true

  defp content_error?(_error), do: false

  defp stop(command, error, stacktrace) do
    Logger.error(
      "Sync push stopped at command #{inspect(command["id"])}: " <>
        Exception.format(:error, error, stacktrace)
    )

    :stop
  end

  defp apply_one(user, command) do
    with {:ok, command} <- validate(command) do
      if recorded?(command.id) do
        result(command.id, "replayed")
      else
        user
        |> dispatch(command)
        |> outcome(command)
      end
    else
      {:error, reason} -> rejected(command, reason, %{})
    end
  end

  defp outcome({:ok, _entity}, command) do
    if recorded?(command.id),
      do: result(command.id, "applied"),
      else: result(command.id, "noop")
  end

  defp outcome({:error, %Ecto.Changeset{} = changeset}, command),
    do: rejected(command, "invalid", errors(changeset))

  defp outcome({:error, reason}, command) when is_atom(reason),
    do: rejected(command, Atom.to_string(reason), %{})

  # Whether the command left a change row: a replay, or an apply that
  # changed something.
  defp recorded?(command_id),
    do: Repo.exists?(from c in Change, where: c.command_id == ^command_id)

  ## Shape

  defp validate(%{} = command) do
    with {:ok, id} <- uuid(command["id"], "invalid_command"),
         {:ok, entity, schema} <- entity(command["entity"]),
         {:ok, entity_id} <- uuid(command["entity_id"], "invalid_command"),
         {:ok, op} <- op(command["op"]),
         {:ok, fields} <- fields(command["fields"], schema.client_fields(op)) do
      {:ok,
       %{
         id: id,
         entity: entity,
         entity_id: entity_id,
         op: op,
         fields: fields,
         at: at(command["at"])
       }}
    end
  end

  defp validate(_command), do: {:error, "invalid_command"}

  defp uuid(value, reason) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, reason}
    end
  end

  defp entity(entity) do
    case Map.fetch(@schemas, entity) do
      {:ok, schema} -> {:ok, entity, schema}
      :error -> {:error, "unknown_entity"}
    end
  end

  defp op("insert"), do: {:ok, :insert}
  defp op("patch"), do: {:ok, :patch}
  defp op(_op), do: {:error, "invalid_op"}

  defp fields(%{} = fields, allowed) do
    case Enum.reject(Map.keys(fields), &(&1 in allowed)) do
      [] -> {:ok, fields}
      _ -> {:error, "field_not_allowed"}
    end
  end

  defp fields(_fields, _allowed), do: {:error, "invalid_command"}

  defp at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      {:error, _} -> nil
    end
  end

  defp at(_value), do: nil

  ## Dispatch

  # A patch that sets discarded_at deletes, whatever else it carries:
  # discard wins (ADR 0014). There is no revive.
  defp dispatch(user, %{op: :patch, fields: %{"discarded_at" => nil}, entity: entity} = command)
       when entity not in ["task_tag", "project_tag"],
       do: dispatch(user, %{command | fields: Map.delete(command.fields, "discarded_at")})

  defp dispatch(user, %{op: :patch, fields: %{"discarded_at" => _}, entity: entity} = command)
       when entity not in ["task_tag", "project_tag"],
       do: delete(user, entity, command.entity_id, command.id)

  defp dispatch(user, %{op: :insert} = command) do
    if exists?(command),
      do: {:error, :exists},
      else:
        insert(user, command.entity, Map.put(command.fields, "id", command.entity_id), command)
  end

  defp dispatch(user, %{op: :patch} = command),
    do: patch(user, command.entity, command.entity_id, command.fields, command)

  defp exists?(%{entity: entity, entity_id: id}),
    do: Repo.exists?(from r in Map.fetch!(@schemas, entity), where: r.id == ^id)

  # The row comes with the user.
  defp insert(_user, "user_preferences", _attrs, _command), do: {:error, :invalid}

  defp insert(user, "task", attrs, command),
    do: Tasks.create_task(user, attrs, command.id, at: command.at)

  defp insert(user, "project", attrs, command),
    do: Projects.create_project(user, attrs, command.id, at: command.at)

  defp insert(user, "project_folder", attrs, command),
    do: ProjectFolders.create_folder(user, attrs, command.id)

  defp insert(user, "recurrence_series", attrs, command),
    do: Recurrence.create_series(user, attrs, command.id)

  defp insert(user, "tag", attrs, command),
    do: Tags.insert_client_tag(user, attrs, command.id)

  defp insert(user, "task_tag", attrs, command),
    do: link(user, :task, attrs["task_id"], attrs["tag_id"], :tag, command)

  defp insert(user, "project_tag", attrs, command),
    do: link(user, :project, attrs["project_id"], attrs["tag_id"], :tag, command)

  defp patch(user, "user_preferences", id, fields, command),
    do: Accounts.update_preferences(user, id, fields, command.id)

  defp patch(user, "task", id, fields, command),
    do: Tasks.patch_task(user, id, fields, command.id, at: command.at)

  defp patch(user, "project", id, fields, command),
    do: Projects.update_project(user, id, fields, command.id, at: command.at)

  defp patch(user, "project_folder", id, fields, command),
    do: ProjectFolders.update_folder(user, id, fields, command.id)

  defp patch(user, "recurrence_series", id, fields, command),
    do: Recurrence.update_series(user, id, fields, command.id)

  defp patch(user, "tag", id, fields, command),
    do: Tags.patch_client_tag(user, id, fields, command.id)

  defp patch(user, kind_tag, id, %{"discarded_at" => discarded_at}, command)
       when kind_tag in ["task_tag", "project_tag"] do
    case Repo.get_owned(Map.fetch!(@schemas, kind_tag), user, id) do
      nil ->
        {:error, :not_found}

      link ->
        kind = if kind_tag == "task_tag", do: :task, else: :project
        owner_id = if kind == :task, do: link.task_id, else: link.project_id
        action = if is_nil(discarded_at), do: :tag, else: :untag
        link(user, kind, owner_id, link.tag_id, action, %{command | entity_id: link.id})
    end
  end

  defp patch(_user, _kind_tag, _id, _fields, _command), do: {:error, :invalid}

  defp delete(user, "task", id, command_id), do: Tasks.delete_task(user, id, command_id)
  defp delete(user, "project", id, command_id), do: Projects.delete_project(user, id, command_id)

  defp delete(user, "project_folder", id, command_id),
    do: ProjectFolders.delete_folder(user, id, command_id)

  defp delete(user, "recurrence_series", id, command_id),
    do: Recurrence.delete_series(user, id, command_id)

  defp delete(user, "tag", id, command_id), do: Tags.delete_tag(user, id, command_id)

  # A link's id is v5 of its pair (ADR 0005). One that does not match the
  # pair it names would split the row across devices.
  defp link(user, kind, owner_id, tag_id, action, command) do
    with {:ok, owner_id} <- uuid(owner_id, :invalid),
         {:ok, tag_id} <- uuid(tag_id, :invalid),
         true <- Link.id(kind, owner_id, tag_id) == command.entity_id || {:error, :invalid_id} do
      case {kind, action} do
        {:task, :tag} -> Tags.tag_task(user, owner_id, tag_id, command.id)
        {:task, :untag} -> Tags.untag_task(user, owner_id, tag_id, command.id)
        {:project, :tag} -> Tags.tag_project(user, owner_id, tag_id, command.id)
        {:project, :untag} -> Tags.untag_project(user, owner_id, tag_id, command.id)
      end
    end
  end

  ## Results

  defp result(id, status), do: %{id: id, status: status}

  defp rejected(command, reason, errors) do
    id = if is_map(command), do: command[:id] || command["id"]

    %{id: id, status: "rejected", reason: reason}
    |> then(fn result -> if errors == %{}, do: result, else: Map.put(result, :errors, errors) end)
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
