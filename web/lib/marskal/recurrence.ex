defmodule Marskal.Recurrence do
  @moduledoc """
  Recurrence series and the occurrences that belong to them (ADR 0007).

  An occurrence is a task (projects later) with `series_id` and
  `occurrence_for`, the slot the rule gave it. It keeps that slot when its
  dates move. The occurrences are the series' history.

  A client joins a task to a series only as its first occurrence. The
  server creates every later one; clients get them on pull (ADR 0014).
  """

  import Ecto.Changeset
  import Ecto.Query
  alias Marskal.Accounts.User
  alias Marskal.Changes
  alias Marskal.Recurrence.Series
  alias Marskal.Repo

  # A made-up constant fixed by ADR 0014 ("0014" is the ADR number).
  # Changing it would give existing slots new ids, so the generator would
  # create them again.
  @namespace "a5c0ffee-0014-5000-8000-000000000014"

  @doc """
  The id of the occurrence a rule creates for `occurrence_for`: v5 of the
  series id and the instant, so two writers that reach the same slot name
  the same row (ADR 0014).
  """
  def occurrence_id(series_id, %DateTime{} = occurrence_for) do
    at =
      occurrence_for
      |> DateTime.shift_zone!("Etc/UTC")
      |> Map.update!(:microsecond, fn {us, _precision} -> {us, 6} end)
      |> DateTime.to_iso8601()

    Marskal.Uuid.v5(@namespace, "#{String.downcase(series_id)}|#{at}")
  end

  @doc "A live series the user owns."
  def get_series(%User{} = user, id) do
    case Repo.get_owned(Series, user, id) do
      %Series{discarded_at: nil} = series -> series
      _ -> nil
    end
  end

  def create_series(%User{} = user, attrs, command_id) do
    Changes.apply(user, command_id, "recurrence_series", fn ->
      changeset = Series.create_changeset(%Series{}, user, attrs)

      case Repo.insert(changeset) do
        {:ok, series} -> {:ok, series, changeset}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc "Patch any part of the rule, or `stopped_at`, in one command."
  def update_series(%User{} = user, id, attrs, command_id) when is_map(attrs) do
    Changes.apply(user, command_id, "recurrence_series", fn ->
      case get_series(user, id) do
        nil ->
          {:error, :not_found}

        series ->
          changeset = Series.update_changeset(series, attrs)

          case Repo.update(changeset) do
            {:ok, series} -> {:ok, series, changeset}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end)
  end

  def stop_series(user, id, command_id),
    do: update_series(user, id, %{stopped_at: DateTime.utc_now(:second)}, command_id)

  @doc """
  Discards the series. Its occurrences stay, as ordinary tasks that keep
  their `series_id` and slot.
  """
  def delete_series(%User{} = user, id, command_id) do
    Changes.apply(user, command_id, "recurrence_series", fn ->
      case get_series(user, id) do
        nil ->
          {:error, :not_found}

        series ->
          changeset = Series.discard_changeset(series)
          {:ok, Repo.update!(changeset), changeset}
      end
    end)
  end

  @doc """
  Checks a row that joins a series in this change: `series_id` and
  `occurrence_for` come together, once, as the first occurrence of a live
  series of `kind` that has not stopped, and `occurrence_for` is the row's
  anchor date.
  """
  def validate_occurrence(changeset, user_id, kind) do
    joining? = changed?(changeset, :series_id) or changed?(changeset, :occurrence_for)

    cond do
      not joining? ->
        changeset

      changeset.data.series_id != nil ->
        add_error(changeset, :series_id, "cannot change once set")

      is_nil(get_field(changeset, :series_id)) or is_nil(get_field(changeset, :occurrence_for)) ->
        add_error(changeset, :occurrence_for, "comes with series_id")

      true ->
        validate_slot(changeset, user_id, kind)
    end
    |> check_constraint(:series_id,
      name: :"#{kind}s_occurrence_fixed",
      message: "cannot change once set"
    )
    |> check_constraint(:occurrence_for,
      name: :"#{kind}s_occurrence_shape",
      message: "comes with series_id"
    )
    |> unique_constraint(:occurrence_for,
      name: :"#{kind}s_series_id_occurrence_for_key",
      message: "is already in the series"
    )
    |> foreign_key_constraint(:series_id,
      name: :"#{kind}s_series_id_fkey",
      message: "must be one of your series"
    )
  end

  defp validate_slot(changeset, user_id, kind) do
    series_id = get_field(changeset, :series_id)

    live =
      Repo.one(
        from s in Series,
          where: s.id == ^series_id and s.user_id == ^user_id and is_nil(s.discarded_at)
      )

    case live do
      %Series{kind: ^kind, stopped_at: nil} = series ->
        cond do
          occurrences?(series) ->
            add_error(changeset, :series_id, "already has its first occurrence")

          get_field(changeset, Series.anchor_field(series)) !=
              get_field(changeset, :occurrence_for) ->
            add_error(changeset, :occurrence_for, "must be the #{series.anchor} date")

          true ->
            changeset
        end

      %Series{kind: ^kind} ->
        add_error(changeset, :series_id, "has stopped")

      _ ->
        add_error(changeset, :series_id, "must be one of your series")
    end
  end

  # Discarded ones too: a deleted first occurrence is still the series'
  # history.
  defp occurrences?(%Series{kind: :task, id: id}),
    do: Repo.exists?(from t in Marskal.Tasks.Task, where: t.series_id == ^id)

  defp occurrences?(%Series{kind: :project, id: id}),
    do: Repo.exists?(from p in Marskal.Projects.Project, where: p.series_id == ^id)
end
