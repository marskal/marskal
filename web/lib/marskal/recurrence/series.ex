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
    :month_days,
    :month_ordinal,
    :month_day_kind,
    :ends_at,
    :end_count,
    :week_start
  ]

  @day_kinds [
    :monday,
    :tuesday,
    :wednesday,
    :thursday,
    :friday,
    :saturday,
    :sunday,
    :work_day,
    :weekend_day
  ]

  @primary_key {:id, Ecto.UUID, autogenerate: false, read_after_writes: true}
  @foreign_key_type Ecto.UUID

  schema "recurrence_series" do
    field :kind, Ecto.Enum, values: [:task, :project]
    field :mode, Ecto.Enum, values: [:regular, :on_completion]
    field :anchor, Ecto.Enum, values: [:defer, :planned, :due]
    field :interval, :integer
    field :frequency, Ecto.Enum, values: [:minutes, :hours, :days, :weeks, :months, :years]
    field :weekdays, {:array, :integer}, default: []
    field :month_days, {:array, :integer}, default: []
    field :month_ordinal, :integer
    field :month_day_kind, Ecto.Enum, values: @day_kinds
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
      :month_days,
      :week_start
    ])
    |> validate_number(:interval, greater_than: 0)
    |> validate_number(:end_count, greater_than: 0)
    |> normalize(:weekdays)
    |> normalize(:month_days)
    |> validate_subset(:weekdays, 1..7)
    |> validate_inclusion(:week_start, 1..7)
    |> validate_subset(:month_days, [-1 | Enum.to_list(1..31)])
    |> validate_inclusion(:month_ordinal, [-1, 1, 2, 3, 4, 5])
    |> only_for(:weeks, :weekdays, [])
    |> only_for(:months, :month_days, [])
    |> only_for(:months, :month_ordinal, nil)
    |> regular_only(:weekdays, [])
    |> regular_only(:month_days, [])
    |> regular_only(:month_ordinal, nil)
    |> validate_month_weekday()
    |> check_constraint(:weekdays, name: :recurrence_series_weekdays)
    |> check_constraint(:month_days, name: :recurrence_series_month_days)
    |> check_constraint(:month_ordinal, name: :recurrence_series_month_weekday)
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

  defp validate_month_weekday(changeset) do
    case {get_field(changeset, :month_ordinal), get_field(changeset, :month_day_kind)} do
      {nil, kind} when not is_nil(kind) ->
        add_error(changeset, :month_ordinal, "can't be blank")

      {ordinal, nil} when not is_nil(ordinal) ->
        add_error(changeset, :month_day_kind, "can't be blank")

      _ ->
        changeset
    end
  end
end
