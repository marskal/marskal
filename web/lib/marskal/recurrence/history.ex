defmodule Marskal.Recurrence.History do
  @moduledoc """
  A series' history and the numbers that encourage a habit (ADR 0007,
  Showing it). Worked out at read time from the occurrences; nothing is
  stored.

  A pure function of the series, its live occurrences in slot order, now,
  and the user's timezone. Missed slots are the rule's slots that passed
  while an occurrence was open. Paused slots are those the rule would have
  filled between a resolution and the next occurrence. Dropped is neutral.
  """

  alias Marskal.Recurrence.Schedule
  alias Marskal.Recurrence.Series

  # Strength weighs a slot half as much 7 slots later.
  @half_life 7
  # Enough for any real gap; a by-the-minute series left for weeks stops
  # counting here.
  @most_slots 1000
  @trend_length 30

  defstruct entries: [],
            strength: 0.0,
            trend: [],
            streak: 0,
            best_streak: 0,
            done: 0,
            dropped: 0,
            missed: 0,
            rate: nil,
            lateness: nil

  @type entry ::
          {:occurrence, map()}
          | {:missed, [DateTime.t()]}
          | {:paused, pos_integer()}

  @doc """
  The history of `series` from `occurrences`, each with `state`,
  `occurrence_for`, and `resolved_at`, oldest slot first. `entries` are
  newest first.
  """
  def build(%Series{} = series, occurrences, %DateTime{} = now, zone) when is_binary(zone) do
    events = events(series, occurrences, now, zone)
    {strength, trend, streak, best} = score(events)
    counts = Enum.frequencies_by(events, &elem(&1, 0))
    done = Map.get(counts, :done, 0)
    dropped = Map.get(counts, :dropped, 0)
    missed = Map.get(counts, :missed, 0)
    counted = done + dropped + missed

    %__MODULE__{
      entries: entries(events),
      strength: strength,
      trend: Enum.take(trend, -@trend_length),
      streak: streak,
      best_streak: best,
      done: done,
      dropped: dropped,
      missed: missed,
      rate: if(counted > 0, do: done / counted),
      lateness: lateness(occurrences)
    }
  end

  # In time order: each occurrence, the slots missed while it was open,
  # its resolution, then any slots paused before the next.
  defp events(series, occurrences, now, zone) do
    occurrences
    |> Enum.chunk_every(2, 1)
    |> Enum.flat_map(fn
      [occurrence, next] -> occurrence_events(series, occurrence, next, now, zone)
      [occurrence] -> occurrence_events(series, occurrence, nil, now, zone)
    end)
  end

  defp occurrence_events(series, occurrence, next, now, zone) do
    until = open_until(occurrence, next, now)
    first = Schedule.next_slot(series, occurrence.occurrence_for, zone)
    {missed, after_missed} = slots(series, first, zone, &(not DateTime.after?(&1, until)))

    paused =
      if next && occurrence.resolved_at do
        start = paused_from(series, after_missed, occurrence, zone)
        {paused, _} = slots(series, start, zone, &DateTime.before?(&1, next.occurrence_for))
        length(paused)
      else
        0
      end

    [{:occurrence, occurrence}] ++
      Enum.map(missed, &{:missed, &1}) ++
      resolution(occurrence) ++
      if(paused > 0, do: [{:paused, paused}], else: [])
  end

  # An occurrence is open until its first resolution. One still open is
  # open until now while it is the latest, and until the next one's slot
  # otherwise.
  defp open_until(%{resolved_at: %DateTime{} = at}, _next, _now), do: at
  defp open_until(_occurrence, nil, now), do: now
  defp open_until(_occurrence, next, _now), do: next.occurrence_for

  # The slot the next occurrence would have had without a pause: in regular
  # mode the one after the missed slots, on completion the interval after
  # the resolution.
  defp paused_from(%Series{mode: :regular}, after_missed, _occurrence, _zone), do: after_missed

  defp paused_from(%Series{mode: :on_completion} = series, _after_missed, occurrence, zone),
    do: Schedule.next_slot(series, occurrence.resolved_at, zone)

  # The slots from `first` on while `keep?` holds, and the first one that
  # does not (nil when the rule ends first).
  defp slots(series, first, zone, keep?) do
    first
    |> Stream.unfold(fn
      nil -> nil
      slot -> {slot, Schedule.next_slot(series, slot, zone)}
    end)
    |> Stream.take(@most_slots)
    |> Enum.reduce_while({[], nil}, fn slot, {kept, _stop} ->
      if keep?.(slot), do: {:cont, {[slot | kept], nil}}, else: {:halt, {kept, slot}}
    end)
    |> then(fn {kept, stop} -> {Enum.reverse(kept), stop} end)
  end

  defp resolution(%{state: :done}), do: [{:done}]
  defp resolution(%{state: :dropped}), do: [{:dropped}]
  defp resolution(_occurrence), do: []

  # Strength is an average weighted to recent slots. Done counts 1 and a
  # missed slot 0; the rest leave it alone.
  defp score(events) do
    keep = :math.pow(0.5, 1 / @half_life)

    {strength, trend, streak, best} =
      Enum.reduce(events, {0.0, [], 0, 0}, fn
        {:done}, {strength, trend, streak, best} ->
          strength = strength * keep + (1 - keep)
          {strength, [strength | trend], streak + 1, max(best, streak + 1)}

        {:missed, _slot}, {strength, trend, _streak, best} ->
          strength = strength * keep
          {strength, [strength | trend], 0, best}

        _event, acc ->
          acc
      end)

    {strength, Enum.reverse(trend), streak, best}
  end

  defp entries(events) do
    events
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.flat_map(fn
      [{:occurrence, _} | _] = occurrences -> occurrences
      [{:missed, _} | _] = missed -> [{:missed, Enum.map(missed, &elem(&1, 1))}]
      [{:paused, _} | _] = paused -> paused
      _resolutions -> []
    end)
    |> Enum.reverse()
  end

  # The median of how long after its slot each Done occurrence was
  # resolved, in seconds; negative when early.
  defp lateness(occurrences) do
    occurrences
    |> Enum.filter(&(&1.state == :done and &1.resolved_at))
    |> Enum.map(&DateTime.diff(&1.resolved_at, &1.occurrence_for))
    |> Enum.sort()
    |> median()
  end

  defp median([]), do: nil

  defp median(sorted) do
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1,
      do: Enum.at(sorted, middle),
      else: div(Enum.at(sorted, middle - 1) + Enum.at(sorted, middle), 2)
  end
end
