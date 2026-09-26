defmodule Marskal.Imports.Xml do
  @moduledoc false

  require Record

  Record.defrecord(
    :xmlElement,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecord(
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecord(:xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  def parse!(xml) when is_binary(xml) do
    # A backup must not pull in a DTD or external entity (XXE).
    xml = xml |> strip_doctype() |> neutralize_entities()

    try do
      # xmerl decodes a byte list as UTF-8. A Unicode codepoint list makes
      # ø (U+00F8) look like an illegal byte.
      {doc, _} =
        xml
        |> :binary.bin_to_list()
        |> :xmerl_scan.string(quiet: true, fetch_fun: &reject_external/2)

      doc
    catch
      :exit, _reason ->
        raise ArgumentError, "Backup XML could not be read."
    end
  end

  def name(xmlElement(name: name)), do: local(name)
  def name(_), do: nil

  def attr(xmlElement(attributes: attrs), key) do
    key = to_string(key)

    Enum.find_value(attrs, fn
      xmlAttribute(name: name, value: value) ->
        if local(name) == key, do: to_text(value)

      _ ->
        nil
    end)
  end

  def children(xmlElement(content: content)) do
    Enum.filter(content, fn
      xmlElement() -> true
      _ -> false
    end)
  end

  def child(element, child_name) do
    Enum.find(children(element), &(name(&1) == child_name))
  end

  def children_named(element, child_name) do
    Enum.filter(children(element), &(name(&1) == child_name))
  end

  def text(element) do
    element
    |> raw_text()
    |> String.trim()
    |> presence()
  end

  def raw_text(xmlElement(content: content)) do
    content
    |> Enum.map(fn
      xmlText(value: value) -> to_text(value)
      _ -> ""
    end)
    |> IO.iodata_to_binary()
  end

  def raw_text(_), do: ""

  def descendant_text(element) do
    element
    |> texts()
    |> IO.iodata_to_binary()
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
    |> presence()
  end

  def remove_named(xmlElement(content: content) = element, names) do
    content =
      Enum.flat_map(content, fn
        xmlElement(name: name) = child ->
          if local(name) in names, do: [], else: [remove_named(child, names)]

        other ->
          [other]
      end)

    xmlElement(element, content: content)
  end

  defp texts(xmlElement(content: content)) do
    Enum.flat_map(content, fn
      xmlText(value: value) -> [to_text(value)]
      xmlElement() = child -> texts(child)
      _ -> []
    end)
  end

  defp local(name) when is_atom(name), do: Atom.to_string(name)
  defp local(name) when is_list(name), do: to_text(name)
  defp local({_ns, name}), do: local(name)

  defp to_text(value) when is_binary(value), do: value
  defp to_text(value) when is_atom(value), do: Atom.to_string(value)

  defp to_text(value) when is_list(value) do
    case :unicode.characters_to_binary(value) do
      binary when is_binary(binary) -> binary
      _ -> ""
    end
  end

  defp to_text(value), do: to_string(value)

  defp presence(""), do: nil
  defp presence(text), do: text

  defp strip_doctype(xml) do
    xml
    |> String.replace(~r/<\?xml[^?]*\?>/s, "")
    |> String.replace(~r/<!DOCTYPE\b[^>\[]*(?:\[[\s\S]*?\])?\s*>/s, "")
  end

  # Leave the five predefined entities. Anything else would have been a DTD name.
  defp neutralize_entities(xml) do
    String.replace(xml, ~r/&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9A-Fa-f]+);)/, "&amp;")
  end

  defp reject_external(_uri, state) do
    {:ok, {[], state}}
  end
end
