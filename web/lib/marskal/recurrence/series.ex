defmodule Marskal.Recurrence.Series do
  @moduledoc """
  A recurrence rule and the identity its occurrences share (ADR 0007).

  The series holds no title, notes, or location: an occurrence copies those
  from the latest one. `stopped_at` ends it without deleting it, so its
  occurrences keep their history.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @rule [
    :mode,
    :anchor,
    :interval,
    :frequency,
    :weekdays,
    :on_days,
    :ends_at,
    :end_count,
    :week_start
  ]

  @weekday_kinds ~w(monday tuesday wednesday thursday friday saturday sunday)a
  @day_kinds @weekday_kinds ++ [:work_day, :weekend_day]

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "recurrence_series" do
    field :kind, Ecto.Enum, values: [:task, :project]
    field :mode, Ecto.Enum, values: [:regular, :on_completion]
    field :anchor, Ecto.Enum, values: [:defer, :planned, :due]
    field :interval, :integer
    field :frequency, Ecto.Enum, values: [:minutes, :hours, :days, :weeks, :months, :years]
    field :weekdays, {:array, :integer}, default: []
    field :on_days, {:array, :string}, default: []
    field :ends_at, :utc_datetime
    field :end_count, :integer
    field :week_start, :integer, default: 1
    field :stopped_at, :utc_datetime
    field :discarded_at, :utc_datetime

    belongs_to :user, Marskal.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  The fields a client may write, by op (ADR 0019). Any other field rejects
  the command. A patch of `discarded_at` is a delete.
  """
  def client_fields(:insert), do: ["kind" | Enum.map(@rule, &Atom.to_string/1)]

  def client_fields(:patch),
    do: Enum.map(@rule, &Atom.to_string/1) ++ ~w(stopped_at discarded_at)

  @doc """
  The days a monthly or yearly rule lands on, as `{month, ordinal, kind}`.
  `month` is 1–12 for a yearly row and nil for a monthly one. `kind` is
  `:day` with an ordinal of 1–31, a weekday with 1–5, `:work_day` with
  1–23, or `:weekend_day` with 1–10: as many as a month can have. An
  ordinal of −1 to −5 counts from the end: −1 is the last, −2 the second
  to last.
  Rows that do not parse are left out; the changeset refuses them.
  """
  def day_rules(%__MODULE__{on_days: days}),
    do: for(day <- days, {:ok, rule} = parse_day(day), do: rule)

  @doc ~S(A day row as stored: `"14:day"`, or `"10:-1:monday"` with its month.)
  def format_day({nil, ordinal, kind}), do: "#{ordinal}:#{kind}"
  def format_day({month, ordinal, kind}), do: "#{month}:#{ordinal}:#{kind}"

  @doc "Parses a stored day row into `{month, ordinal, kind}`."
  def parse_day(day) when is_binary(day) do
    case String.split(day, ":") do
      [ordinal, kind] -> build_day(nil, ordinal, kind)
      [month, ordinal, kind] -> build_day(month, ordinal, kind)
      _ -> :error
    end
  end

  def parse_day(_day), do: :error

  defp build_day(month, ordinal, kind) do
    with {:ok, month} <- parse_month(month),
         {ordinal, ""} <- Integer.parse(ordinal),
         kind when kind in [:day | @day_kinds] <- parse_kind(kind),
         true <- ordinal_fits?(ordinal, kind) do
      {:ok, {month, ordinal, kind}}
    else
      _ -> :error
    end
  end

  defp parse_month(nil), do: {:ok, nil}

  defp parse_month(month) do
    case Integer.parse(month) do
      {month, ""} when month in 1..12 -> {:ok, month}
      _ -> :error
    end
  end

  defp parse_kind(kind) do
    Enum.find([:day | @day_kinds], &(Atom.to_string(&1) == kind))
  end

  defp ordinal_fits?(ordinal, kind), do: ordinal in -5..-1//1 or ordinal in 1..most(kind)

  @doc "The highest ordinal a kind of day takes: as many as a month can have."
  def most(:day), do: 31
  def most(:work_day), do: 23
  def most(:weekend_day), do: 10
  def most(_weekday), do: 5

  @doc "The date field an occurrence's anchor is."
  def anchor_field(%__MODULE__{anchor: :defer}), do: :defer_until
  def anchor_field(%__MODULE__{anchor: :planned}), do: :planned_at
  def anchor_field(%__MODULE__{anchor: :due}), do: :due_at

  def create_changeset(series, user, attrs) do
    series
    |> cast(attrs, [:id, :kind | @rule])
    |> validate_required([:kind])
    # Recurring projects come with copying a project's task tree (ADR 0007).
    |> validate_inclusion(:kind, [:task], message: "projects do not repeat yet")
    |> put_change(:user_id, user.id)
    |> put_week_start(user)
    |> validate_rule()
  end

  @doc """
  Any subset of the rule and `stopped_at`. A change to any part of the rule
  patches all of it, so two offline edits merge into one whole rule, not a
  mix of both (as Defer does, ADR 0006).
  """
  def update_changeset(series, attrs) do
    changeset =
      series
      |> cast(attrs, [:stopped_at | @rule])
      |> validate_rule()

    if Enum.any?(@rule, &changed?(changeset, &1)),
      do: Enum.reduce(@rule, changeset, &force_change(&2, &1, get_field(&2, &1))),
      else: changeset
  end

  # A series keeps the week start the user had when it was made, so a
  # later change to the setting does not move its slots (ADR 0007). It is
  # always in the insert's patch, even when it is the default.
  defp put_week_start(changeset, user) do
    week_start =
      if Map.has_key?(changeset.params, "week_start"),
        do: get_field(changeset, :week_start),
        else: Marskal.Accounts.preferences(user).week_start

    force_change(changeset, :week_start, week_start)
  end

  def discard_changeset(series), do: Marskal.Dates.discard(series)

  defp validate_rule(changeset) do
    changeset
    |> validate_required([
      :mode,
      :anchor,
      :interval,
      :frequency,
      :weekdays,
      :on_days,
      :week_start
    ])
    |> validate_number(:interval, greater_than: 0)
    |> validate_number(:end_count, greater_than: 0)
    |> normalize(:weekdays)
    |> validate_subset(:weekdays, 1..7)
    |> validate_inclusion(:week_start, 1..7)
    |> validate_on_days()
    |> only_for(:weeks, :weekdays, [])
    |> regular_only(:weekdays, [])
    |> regular_only(:on_days, [])
    |> check_constraint(:weekdays, name: :recurrence_series_weekdays)
    |> check_constraint(:on_days, name: :recurrence_series_on_days)
    |> check_constraint(:week_start, name: :recurrence_series_week_start)
  end

  # Sorted and without repeats, so the same days are the same value.
  defp normalize(changeset, field) do
    case fetch_change(changeset, field) do
      {:ok, days} when is_list(days) ->
        put_change(changeset, field, days |> Enum.uniq() |> Enum.sort())

      _ ->
        changeset
    end
  end

  defp only_for(changeset, frequency, field, empty) do
    if get_field(changeset, :frequency) != frequency and get_field(changeset, field) != empty,
      do: add_error(changeset, field, "only applies to a rule every so many #{frequency}"),
      else: changeset
  end

  # On completion is an interval from the resolution, with no day limits
  # yet (ADR 0007).
  defp regular_only(changeset, field, empty) do
    if get_field(changeset, :mode) == :on_completion and get_field(changeset, field) != empty,
      do: add_error(changeset, field, "only applies to a regular rule"),
      else: changeset
  end

  # Each row parses, and has a month exactly when the rule is yearly. Kept
  # without repeats, in calendar order, so the same days are the same value.
  defp validate_on_days(changeset) do
    frequency = get_field(changeset, :frequency)
    days = get_field(changeset, :on_days) || []
    parsed = Enum.map(days, &parse_day/1)

    cond do
      days != [] and frequency not in [:months, :years] ->
        add_error(changeset, :on_days, "only applies to a monthly or yearly rule")

      Enum.any?(parsed, &(not fits?(&1, frequency))) ->
        add_error(changeset, :on_days, "has a day that does not fit the rule")

      changed?(changeset, :on_days) ->
        sorted = parsed |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort_by(&day_order/1)
        put_change(changeset, :on_days, Enum.map(sorted, &format_day/1))

      true ->
        changeset
    end
  end

  defp fits?({:ok, {nil, _ordinal, _kind}}, :months), do: true
  defp fits?({:ok, {month, _ordinal, _kind}}, :years) when is_integer(month), do: true
  defp fits?(_parsed, _frequency), do: false

  # Month, then numbered days before nth weekdays, those counted from the
  # end after the rest, the last one last.
  defp day_order({month, ordinal, kind}) do
    {month || 0, if(kind == :day, do: 0, else: 1),
     if(ordinal < 0, do: 100 + ordinal, else: ordinal),
     Enum.find_index([:day | @day_kinds], &(&1 == kind))}
  end
end
