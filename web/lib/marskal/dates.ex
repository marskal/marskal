defmodule Marskal.Dates do
  @moduledoc """
  Defer, Planned, and Due on tasks and projects (ADR 0006).

  The three are stored as UTC instants. People pick a day and, optionally,
  a time on the wall clock of their stored zone; a day with no time takes
  the field's default time.

  The changeset helpers here are shared by `Marskal.Tasks.Task` and
  `Marskal.Projects.Project`, so the two keep the same semantics.
  """

  import Ecto.Changeset

  @fields [:defer_until, :deferred_indefinitely, :planned_at, :due_at]
  # resolved_at is here for imports whose source gives only a day.
  @default_times %{
    defer_until: ~T[00:00:00],
    planned_at: ~T[09:00:00],
    due_at: ~T[17:00:00],
    resolved_at: ~T[00:00:00]
  }

  @doc "The date fields a patch may carry."
  def fields, do: @fields

  @doc "The wall-clock time a day gets when no time is picked."
  def default_time(field), do: Map.fetch!(@default_times, field)

  ## Predicates

  @doc """
  Still deferred at `now`: indefinitely, or until a later instant. After the
  until instant passes, the record is not deferred.
  """
  def deferred?(%{deferred_indefinitely: true}, _now), do: true
  def deferred?(%{defer_until: %DateTime{} = until}, now), do: DateTime.before?(now, until)
  def deferred?(_record, _now), do: false

  @doc "Open and at or past its due instant."
  def overdue?(%{state: :to_do, due_at: %DateTime{} = due}, now),
    do: not DateTime.after?(due, now)

  def overdue?(_record, _now), do: false

  ## Changesets

  @doc """
  Keeps Defer to one shape. Choosing indefinite clears the until instant,
  and choosing an instant clears indefinite. Either change patches both
  fields, so two offline edits merge into one shape (ADR 0014).
  """
  def put_defer(changeset) do
    indefinite = fetch_change(changeset, :deferred_indefinitely)
    until = fetch_change(changeset, :defer_until)

    cond do
      indefinite == {:ok, true} and match?({:ok, %DateTime{}}, until) ->
        add_error(changeset, :defer_until, "cannot be set when deferred indefinitely")

      indefinite == {:ok, true} ->
        defer(changeset, nil, true)

      match?({:ok, %DateTime{}}, until) ->
        defer(changeset, get_field(changeset, :defer_until), false)

      indefinite == :error and until == :error ->
        changeset

      true ->
        defer(
          changeset,
          get_field(changeset, :defer_until),
          get_field(changeset, :deferred_indefinitely)
        )
    end
    |> validate_required([:deferred_indefinitely])
  end

  defp defer(changeset, until, indefinite) do
    changeset
    |> force_change(:defer_until, until)
    |> force_change(:deferred_indefinitely, indefinite)
  end

  @doc """
  Sets `resolved_at` on the first move to Done or Dropped. A later resolve,
  after a reopen, leaves it alone (ADR 0014).
  """
  def put_resolved_at(changeset) do
    resolving? = get_field(changeset, :state) in [:done, :dropped]

    if resolving? and is_nil(get_field(changeset, :resolved_at)),
      do: put_change(changeset, :resolved_at, DateTime.utc_now(:second)),
      else: changeset
  end

  @doc "Marks the record discarded. Later patches to it are ignored (ADR 0014)."
  def discard(record) do
    change(record, discarded_at: DateTime.utc_now(:second))
  end

  ## Wall clock

  @doc "Today in `zone`."
  def today(zone), do: DateTime.now!(zone) |> DateTime.to_date()

  @doc """
  The instant for `date` at `time` in `zone`. A nil time takes the field's
  default. A time skipped by a DST change moves forward; a repeated one
  takes the first.
  """
  def from_local(%Date{} = date, time, field, zone) do
    case DateTime.new(date, time || default_time(field), zone) do
      {:ok, datetime} -> to_utc(datetime)
      {:gap, _before, just_after} -> to_utc(just_after)
      {:ambiguous, first, _second} -> to_utc(first)
    end
  end

  @doc "The day and time of an instant on the wall clock of `zone`."
  def to_local(%DateTime{} = datetime, zone) do
    local = DateTime.shift_zone!(datetime, zone)
    {DateTime.to_date(local), DateTime.to_time(local) |> Time.truncate(:second)}
  end

  @doc "The instants that bound `date` in `zone`, as `{from, until}`, until exclusive."
  def day_bounds(%Date{} = date, zone) do
    {start_of(date, zone), start_of(Date.add(date, 1), zone)}
  end

  defp start_of(date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, datetime} -> to_utc(datetime)
      {:gap, _before, just_after} -> to_utc(just_after)
      {:ambiguous, first, _second} -> to_utc(first)
    end
  end

  @doc """
  An instant from an imported value: an ISO 8601 date, a floating local
  datetime, or one with an offset. Date-only and floating values are read
  in `zone`. Anything else is nil.
  """
  def parse_source(value, field, zone) when is_binary(value) do
    value = String.trim(value)

    with {:error, _} <- absolute(value),
         {:error, _} <- floating(value, zone),
         {:error, _} <- day(value, field, zone) do
      nil
    else
      {:ok, datetime} -> datetime
    end
  end

  def parse_source(_value, _field, _zone), do: nil

  defp absolute(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, to_utc(datetime)}
      {:error, _} = error -> error
    end
  end

  defp floating(value, zone) do
    with {:ok, naive} <- NaiveDateTime.from_iso8601(value) do
      {:ok, from_local(NaiveDateTime.to_date(naive), NaiveDateTime.to_time(naive), nil, zone)}
    end
  end

  defp day(value, field, zone) do
    with {:ok, date} <- Date.from_iso8601(value) do
      {:ok, from_local(date, nil, field, zone)}
    end
  end

  defp to_utc(datetime) do
    datetime |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)
  end
end
