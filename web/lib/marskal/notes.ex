defmodule Marskal.Notes do
  @moduledoc """
  Render task and project notes as CommonMark.

  Raw HTML in the source is escaped, then the result is sanitized.
  """

  def html(nil), do: ""
  def html(""), do: ""

  def html(text) when is_binary(text) do
    MDEx.to_html!(text,
      extension: [
        strikethrough: true,
        autolink: true,
        table: true,
        tasklist: true,
        tagfilter: true
      ],
      syntax_highlight: nil,
      sanitize: MDEx.Document.default_sanitize_options()
    )
  end
end
