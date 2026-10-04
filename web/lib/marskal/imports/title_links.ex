defmodule Marskal.Imports.TitleLinks do
  @moduledoc """
  Moves the links out of a source title that is written in Markdown
  (ADR 0022). Each `[text](url)` becomes its text. The first link becomes
  the URL, and the rest are returned as Markdown for the notes. A title
  with no such link but a bare web address keeps its words, and the
  address becomes the URL.

  A link that could not be a URL, such as `javascript:`, stays as written.
  """

  alias Marskal.Url

  # One level of parentheses inside the address, as in Wikipedia links.
  @link ~r/\[([^\[\]]*)\]\(([^()\s]*(?:\([^()\s]*\)[^()\s]*)*)\)/u
  @bare ~r/https?:\/\/[^\s<>]+/u

  @doc "`{title, url, further_links}`; `url` is nil when there is none."
  def split(title) when is_binary(title) do
    links =
      @link
      |> Regex.scan(title)
      |> Enum.filter(fn [_whole, _text, url] -> Url.valid?(url) end)

    case links do
      [] ->
        {title, bare_url(title), []}

      [[_, _, url] | rest] ->
        plain =
          links
          |> Enum.reduce(title, fn [whole, text, url], acc ->
            String.replace(acc, whole, label(text, url), global: false)
          end)
          |> String.replace(~r/\s+/u, " ")
          |> String.trim()

        {plain, url, Enum.map(rest, fn [_, text, url] -> "[#{label(text, url)}](#{url})" end)}
    end
  end

  @doc "Notes with the further links of `split/1` after them, one per line."
  def notes(notes, []), do: notes
  def notes(nil, links), do: Enum.map_join(links, "\n", &("- " <> &1))
  def notes(notes, links), do: notes <> "\n\n" <> notes(nil, links)

  defp label(text, url) do
    case String.trim(text) do
      "" -> url
      text -> text
    end
  end

  defp bare_url(title) do
    with [url] <- Regex.run(@bare, title),
         url = trim_punctuation(url),
         true <- Url.valid?(url) do
      url
    else
      _ -> nil
    end
  end

  # Trailing sentence punctuation is not part of the address, nor is a
  # closing parenthesis that nothing in it opened.
  defp trim_punctuation(url) do
    url = String.replace(url, ~r/[.,;:!?]+\z/u, "")

    if String.ends_with?(url, ")") and not String.contains?(url, "("),
      do: trim_punctuation(String.slice(url, 0..-2//1)),
      else: url
  end
end
