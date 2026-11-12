defmodule MarskalWeb.ReviewIntervals do
  @moduledoc """
  Choosing a review interval and saying it in words (ADR 0026).

  The picker offers Never, a few presets, and Custom, a text field that
  takes the ISO 8601 form. A picker posts `choice` (a preset's ISO form,
  "never", or "custom") and `custom` (the text field), which `read/2`
  turns into the value to save.
  """

  use MarskalWeb, :html

  alias Marskal.ReviewInterval

  @presets ["P7D", "P14D", "P1M", "P3M", "P1Y"]

  @doc "The picker's options, as `{label, value}`."
  def options do
    [{gettext("Never"), "never"}] ++
      Enum.map(@presets, &{words(cast!(&1)), &1}) ++
      [{gettext("Custom…"), "custom"}]
  end

  @doc ~s(The option an interval selects: its preset, "never", or "custom".)
  def choice(nil), do: "never"

  def choice(%Duration{} = interval) do
    Enum.find(@presets, "custom", &(cast!(&1) == interval))
  end

  @doc """
  What a picker's post means: `{:ok, interval}` (nil for Never),
  `{:error, message}` for custom text that is not an interval, or
  `:pending` for Custom with nothing typed yet.
  """
  def read("never", _custom), do: {:ok, nil}

  def read("custom", custom) do
    case String.trim(custom || "") do
      "" -> :pending
      text -> read_custom(text)
    end
  end

  def read(preset, _custom) when preset in @presets, do: {:ok, cast!(preset)}
  def read(_choice, _custom), do: {:error, gettext("Pick an interval.")}

  defp read_custom(text) do
    case ReviewInterval.cast(text) do
      {:ok, interval} ->
        if ReviewInterval.valid?(interval),
          do: {:ok, interval},
          else: {:error, gettext("Use whole days, weeks, months, or years, such as P2W3D.")}

      :error ->
        {:error, gettext("Can't read that. Write it as P, then a number and Y, M, W, or D.")}
    end
  end

  @doc """
  The interval in words: whole weeks as weeks, a single unit as that unit,
  and a mixed one in its parts. Nil is Never.
  """
  def words(nil), do: gettext("Never")

  def words(%Duration{year: 0, month: 0, day: days}) when days > 0 and rem(days, 7) == 0,
    do: weeks(div(days, 7))

  def words(%Duration{year: years, month: 0, day: 0}) when years > 0,
    do: ngettext("Every year", "Every %{count} years", years)

  def words(%Duration{year: 0, month: months, day: 0}) when months > 0,
    do: ngettext("Every month", "Every %{count} months", months)

  def words(%Duration{year: 0, month: 0, day: days}) when days > 0,
    do: ngettext("Every day", "Every %{count} days", days)

  def words(%Duration{} = interval) do
    parts =
      [
        interval.year > 0 && ngettext("1 year", "%{count} years", interval.year),
        interval.month > 0 && ngettext("1 month", "%{count} months", interval.month),
        interval.day > 0 && ngettext("1 day", "%{count} days", interval.day)
      ]
      |> Enum.filter(& &1)

    gettext("Every %{parts}", parts: Enum.join(parts, ", "))
  end

  defp weeks(weeks), do: ngettext("Every week", "Every %{count} weeks", weeks)

  defp cast!(text) do
    {:ok, interval} = ReviewInterval.cast(text)
    interval
  end

  attr :id, :string, required: true
  attr :name, :string, required: true, doc: "the param the choice posts as"
  attr :custom_name, :string, required: true, doc: "the param the custom text posts as"
  attr :label, :string, required: true
  attr :interval, :any, required: true, doc: "the saved interval, or nil for Never"
  attr :choice, :string, default: nil, doc: "the option shown, when it differs from the saved one"
  attr :custom, :string, default: nil, doc: "the custom text as typed"
  attr :error, :string, default: nil

  @doc """
  The interval picker: a select, and for Custom a text field with the
  interval in words beside it and a link to the format's help.
  """
  def picker(assigns) do
    assigns =
      assigns
      |> assign_new(:shown_choice, fn -> assigns.choice || choice(assigns.interval) end)
      |> then(fn assigns ->
        assign(assigns, :custom_text, custom_text(assigns))
      end)
      |> then(&assign(&1, :preview, preview(&1)))

    ~H"""
    <div class="field review-interval" id={@id}>
      <label for={"#{@id}-choice"}>{@label}</label>
      <select id={"#{@id}-choice"} class="input" name={@name}>
        <option :for={{label, value} <- options()} value={value} selected={value == @shown_choice}>
          {label}
        </option>
      </select>
      <div :if={@shown_choice == "custom"} class="review-interval__custom">
        <input
          id={"#{@id}-custom"}
          class="input"
          type="text"
          name={@custom_name}
          value={@custom_text}
          placeholder="P2W3D"
          autocomplete="off"
          spellcheck="false"
          aria-describedby={"#{@id}-words"}
          phx-debounce="300"
        />
        <p id={"#{@id}-words"} class={["hint", @error && "error"]} aria-live="polite">
          {@error || @preview}
        </p>
        <.link href={~p"/help/review-intervals"} class="hint" target="_blank">
          {gettext("How to write an interval")}
        </.link>
      </div>
    </div>
    """
  end

  defp custom_text(%{custom: custom}) when is_binary(custom), do: custom
  defp custom_text(%{interval: %Duration{} = interval}), do: Duration.to_iso8601(interval)
  defp custom_text(_assigns), do: ""

  defp preview(%{error: error}) when is_binary(error), do: nil

  defp preview(%{custom_text: text}) do
    case read("custom", text) do
      {:ok, interval} -> words(interval)
      _ -> nil
    end
  end
end
