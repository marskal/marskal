defmodule Marskal.Imports.Taskpaper do
  @moduledoc """
  Reads and writes a TaskPaper outline (ADR 0013).

  A project ends with a colon, then optional tags. A task starts with a
  dash and a space, or is a dash alone. Any other line is a note under the
  nearest shallower item. One tab, or four spaces, is one level. A tag is
  `@name` or `@name(value)` after whitespace; `)`, `(`, `\\`, and `,` are
  escaped in a value, and a list value is written comma-separated. A
  leading `\\` keeps a note that would otherwise be a task or a project.
  TaskPaper has no escape for `@`, so text that would read as a tag gets a
  word joiner (U+2060) before the `@`. It is invisible, and other tools do
  not read a tag there either; reading drops it again.
  """

  @guard "\u2060"

  @outline "This file is not a TaskPaper outline. A task starts with a dash, and a project ends with a colon."

  defstruct type: :task, text: "", notes: [], tags: [], children: [], depth: 0

  @doc "Whether the first lines hold a task or a project. Invalid UTF-8 does not."
  def outline?(bytes) when is_binary(bytes) do
    if String.valid?(bytes) do
      bytes
      |> strip_bom()
      |> lines()
      |> Enum.take(80)
      |> Enum.any?(&structural_line?/1)
    else
      false
    end
  end

  def outline?(_bytes), do: false

  @doc "The outline as `{items, skipped}`. `skipped` counts notes with nothing above them."
  def parse(text) when is_binary(text) do
    if String.valid?(text) do
      {items, skipped} =
        text
        |> strip_bom()
        |> lines()
        |> Enum.reduce({[], 0}, &consume/2)

      if items == [] do
        raise ArgumentError, @outline
      else
        {finish(items), skipped}
      end
    else
      raise ArgumentError, "This file is not UTF-8 text."
    end
  end

  @doc "Items back to an outline, one tab per level, with a trailing newline on each line."
  def dump(items) when is_list(items) do
    items
    |> Enum.map(&dump_item(&1, 0))
    |> IO.iodata_to_binary()
  end

  defp consume(line, acc) do
    {depth, content} = indent(line)

    if String.trim(content) == "" do
      attach_blank(acc)
    else
      case classify(content) do
        {:note, text, tags} -> attach_note(acc, depth, text, tags)
        {type, text, tags} -> prepend(acc, type, text, tags, depth)
      end
    end
  end

  defp attach_blank({[head | rest], skipped}) do
    {[%{head | notes: ["" | head.notes]} | rest], skipped}
  end

  defp attach_blank(acc), do: acc

  defp prepend({items, skipped}, type, text, tags, depth) do
    item = %__MODULE__{type: type, text: text, tags: tags, depth: depth}
    {[item | items], skipped}
  end

  # Notes are newest-first, so the first shallower item is the parent.
  defp attach_note({items, skipped}, depth, text, tags) do
    case Enum.find_index(items, &(&1.depth < depth)) do
      nil ->
        {items, skipped + 1}

      index ->
        {List.update_at(items, index, &add_note(&1, text, tags)), skipped}
    end
  end

  defp add_note(item, "", tags), do: %{item | tags: item.tags ++ tags}

  defp add_note(item, text, tags) do
    %{item | notes: [text | item.notes], tags: item.tags ++ tags}
  end

  defp finish(items) do
    items
    |> Enum.reverse()
    |> Enum.map(&finish_notes/1)
    |> nest(-1)
    |> elem(0)
  end

  defp finish_notes(item) do
    notes =
      item.notes
      |> Enum.reverse()
      |> Enum.join("\n")
      |> String.trim()

    %{item | notes: notes}
  end

  defp nest([], _min), do: {[], []}

  defp nest([%{depth: depth} = item | rest], min) when depth <= min, do: {[], [item | rest]}

  defp nest([item | rest], min) do
    {children, rest} = nest(rest, item.depth)
    {siblings, rest} = nest(rest, min)
    {[%{item | children: children} | siblings], rest}
  end

  defp classify(content) do
    case strip_escape(content) do
      {:note, text} -> note(text)
      :plain -> plain(content)
    end
  end

  defp strip_escape(<<"\\", rest::binary>>) do
    if structural?(rest), do: {:note, rest}, else: :plain
  end

  defp strip_escape(_content), do: :plain

  defp plain(content) do
    if task?(content) do
      {text, tags} = extract_tags(task_body(content))
      {:task, one_line(text), tags}
    else
      case split_project(content) do
        {:ok, name, tags} -> {:project, one_line(name), tags}
        :error -> note(content)
      end
    end
  end

  defp note(content) do
    {text, tags} = extract_tags(content)
    {:note, text |> String.trim() |> unguard(), tags}
  end

  defp structural?(content), do: task?(content) or match?({:ok, _, _}, split_project(content))

  defp structural_line?(line) do
    {_depth, content} = indent(line)
    structural?(content)
  end

  defp task?("-"), do: true
  defp task?(<<"-", c, _rest::binary>>) when c in [?\s, ?\t], do: true
  defp task?(_content), do: false

  defp task_body("-"), do: ""
  defp task_body(<<"-", c, rest::binary>>) when c in [?\s, ?\t], do: rest

  # The project colon is the last one with only tags after it, so a colon
  # in the name stays in the name and a tag before the colon stays there too.
  defp split_project(content) do
    content
    |> :binary.matches(":")
    |> Enum.reverse()
    |> Enum.find_value(fn {index, _len} ->
      name = binary_part(content, 0, index)
      suffix = binary_part(content, index + 1, byte_size(content) - index - 1)

      case tags_only(suffix) do
        {:ok, tags} -> {:ok, name, tags}
        :error -> nil
      end
    end) || :error
  end

  defp tags_only(text), do: consume_tags(String.trim_leading(text), [])

  defp consume_tags("", acc), do: {:ok, Enum.reverse(acc)}

  defp consume_tags(<<"@", rest::binary>>, acc) do
    case take_tag(rest) do
      {:ok, name, value, rest} -> consume_tags(String.trim_leading(rest), [{name, value} | acc])
      :error -> :error
    end
  end

  defp consume_tags(_text, _acc), do: :error

  defp extract_tags(text), do: extract_tags(text, "", [])

  defp extract_tags("", acc, tags), do: {acc, Enum.reverse(tags)}

  defp extract_tags(<<"@", rest::binary>>, acc, tags) do
    if tag_boundary?(acc) do
      case take_tag(rest) do
        {:ok, name, value, rest} ->
          extract_tags(rest, trim_one_space(acc), [{name, value} | tags])

        :error ->
          extract_tags(rest, acc <> "@", tags)
      end
    else
      extract_tags(rest, acc <> "@", tags)
    end
  end

  defp extract_tags(<<char::utf8, rest::binary>>, acc, tags) do
    extract_tags(rest, acc <> <<char::utf8>>, tags)
  end

  defp tag_boundary?(""), do: true
  defp tag_boundary?(acc), do: String.ends_with?(acc, " ") or String.ends_with?(acc, "\t")

  defp trim_one_space(acc), do: String.replace(acc, ~r/[ \t]\z/, "")

  # Values stay raw, backslashes included, so a comma can be split before it
  # is unescaped.
  defp take_tag(text) do
    case take_name(text, "") do
      {"", _rest} ->
        :error

      {name, <<"(", rest::binary>>} ->
        case take_value(rest, "") do
          {:ok, value, rest} -> {:ok, name, value, rest}
          :error -> :error
        end

      {name, rest} ->
        {:ok, name, nil, rest}
    end
  end

  defp take_name(<<char::utf8, rest::binary>>, acc)
       when char not in [?\s, ?\t, ?@, ?(, ?), ?\n, ?\r] do
    take_name(rest, acc <> <<char::utf8>>)
  end

  defp take_name(rest, acc), do: {acc, rest}

  defp take_value(<<"\\", char::utf8, rest::binary>>, acc) do
    take_value(rest, acc <> "\\" <> <<char::utf8>>)
  end

  defp take_value(<<")", rest::binary>>, acc), do: {:ok, acc, rest}
  defp take_value(<<char::utf8, rest::binary>>, acc), do: take_value(rest, acc <> <<char::utf8>>)
  defp take_value("", _acc), do: :error

  defp indent(line), do: indent(line, 0)
  defp indent(<<"\t", rest::binary>>, level), do: indent(rest, level + 1)
  defp indent(<<"    ", rest::binary>>, level), do: indent(rest, level + 1)
  defp indent(rest, level), do: {level, rest}

  defp one_line(text) do
    text
    |> String.trim()
    |> String.replace(~r/[ \t]+/u, " ")
    |> unguard()
  end

  # An `@` where a tag could start, followed by what a tag name takes.
  defp guard(text), do: String.replace(text, ~r/(^|[ \t])@(?=[^\s@()])/u, "\\1#{@guard}@")

  defp unguard(text), do: String.replace(text, @guard <> "@", "@")

  defp dump_item(item, depth) do
    [
      pad(depth),
      line(item),
      "\n",
      dump_notes(item.notes, depth + 1),
      Enum.map(item.children, &dump_item(&1, depth + 1))
    ]
  end

  defp line(%{type: :project, text: text, tags: tags}),
    do: [guard(text), ":", format_tags(tags)]

  defp line(%{type: :task, text: "", tags: tags}), do: ["-", format_tags(tags)]
  defp line(%{type: :task, text: text, tags: tags}), do: ["- ", guard(text), format_tags(tags)]

  defp format_tags(tags), do: Enum.map(tags, &format_tag/1)
  defp format_tag({name, nil}), do: [" @", name]

  defp format_tag({name, values}) when is_list(values),
    do: [" @", name, "(", Enum.map_join(values, ", ", &escape_value/1), ")"]

  defp format_tag({name, value}), do: [" @", name, "(", escape_value(value), ")"]

  defp escape_value(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> String.replace(",", "\\,")
  end

  defp dump_notes(notes, _depth) when notes in [nil, ""], do: []

  defp dump_notes(notes, depth) do
    pad = pad(depth)

    notes
    |> String.split("\n")
    |> Enum.map(fn line -> [pad, escape_note(line), "\n"] end)
  end

  defp escape_note(line) do
    line = guard(line)
    if structural?(line), do: "\\" <> line, else: line
  end

  defp pad(depth), do: String.duplicate("\t", depth)

  defp lines(text), do: String.split(text, ~r/\r\n|\r|\n/)
  defp strip_bom(<<"\uFEFF", rest::binary>>), do: rest
  defp strip_bom(text), do: text
end
