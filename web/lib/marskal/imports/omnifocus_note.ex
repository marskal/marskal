defmodule Marskal.Imports.OmnifocusNote do
  @moduledoc false

  alias Marskal.Imports.Xml

  @href ~r/\Ahttps?:\/\/[^\s]+\z/i

  def to_markdown(nil), do: nil

  def to_markdown(node) do
    paragraphs =
      paragraph_nodes(node)
      |> Enum.map(&paragraph_markdown/1)
      |> Enum.reject(&(&1 in [nil, ""]))

    text =
      if paragraphs != [] do
        Enum.join(paragraphs, "\n\n")
      else
        fallback(node)
      end

    presence(text)
  end

  defp paragraph_nodes(node) do
    root = Xml.child(node, "text") || node
    Xml.children_named(root, "p")
  end

  defp paragraph_markdown(paragraph) do
    runs = Xml.children_named(paragraph, "run")

    if runs != [] do
      Enum.map_join(runs, &run_markdown/1)
    else
      paragraph
      |> Xml.children()
      |> Enum.flat_map(&Xml.children_named(&1, "lit"))
      |> Enum.map_join(&Xml.text/1)
    end
  end

  defp run_markdown(run) do
    lit = run |> Xml.child("lit") |> Xml.raw_text()
    if lit == "", do: "", else: link(emphasize(lit, run), run)
  end

  defp link(text, run) do
    href = style_value(run, "link")

    if href =~ @href do
      "[#{escape_label(text)}](#{href})"
    else
      text
    end
  end

  defp emphasize(text, run) do
    text
    |> maybe_wrap(struck?(run), "~~")
    |> maybe_wrap(italic?(run), "*")
    |> maybe_wrap(bold?(run), "**")
  end

  defp maybe_wrap(text, true, mark), do: mark <> text <> mark
  defp maybe_wrap(text, false, _mark), do: text

  defp bold?(run) do
    weight = style_value(run, "font-weight")
    weight =~ ~r/\A[6-9]\z/ or truthy?(style_value(run, "font-bold"))
  end

  defp italic?(run), do: truthy?(style_value(run, "font-italic"))

  defp struck?(run) do
    style = style_value(run, "strikethrough-style")
    style not in ["", "none", "0"] or truthy?(style_value(run, "strikethrough"))
  end

  defp style_value(run, key) do
    case Xml.child(run, "style") do
      nil ->
        ""

      style ->
        style
        |> Xml.children_named("value")
        |> Enum.find_value("", fn value ->
          if Xml.attr(value, "key") == key, do: String.trim(Xml.text(value) || "")
        end)
    end
  end

  defp truthy?(value), do: String.downcase(value) in ~w(true 1 yes)

  defp escape_label(text), do: text |> String.replace("[", "\\[") |> String.replace("]", "\\]")

  defp fallback(node) do
    node
    |> Xml.remove_named(["style", "value", "color"])
    |> Xml.descendant_text()
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(text), do: text
end
