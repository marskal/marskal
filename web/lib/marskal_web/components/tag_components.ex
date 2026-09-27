defmodule MarskalWeb.TagComponents do
  @moduledoc """
  Tag paths and chips (ADR 0005). A path is shown as segments with a `›`
  element between them, never as a joined string, so a name holding `/` or
  `:` stays one segment.
  """
  use MarskalWeb, :html

  alias Marskal.Tags.Tag

  attr :tag, Tag, required: true
  attr :class, :any, default: nil

  def path(assigns) do
    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.tag-path) {
        :scope {
          display: inline-flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: 0 0.3em;
          min-width: 0;
        }

        .sep {
          color: var(--muted);
        }

        .ancestor {
          color: var(--muted);
        }
      }
    </style>
    <span class={["tag-path", @class]}>
      <%= for segment <- @tag.parent_path do %>
        <span class="ancestor">{segment}</span>
        <span class="sep" aria-hidden="true">›</span>
      <% end %>
      <span class="name">{@tag.name}</span>
    </span>
    """
  end

  @doc "A tag path as plain text, for titles and labels."
  def path_text(%Tag{} = tag), do: Enum.join(Tag.path(tag), " › ")

  attr :entries, :list, required: true, doc: "effective tags: %{tag: tag, inherited: boolean}"

  def chips(assigns) do
    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.tag-chips) {
        :scope {
          display: flex;
          flex-wrap: wrap;
          gap: 0.3rem;
          margin: 0.4rem 0 0;
          padding: 0;
          list-style: none;
          font-size: 0.8rem;
        }

        a {
          display: inline-flex;
          padding: 0.05rem 0.5rem;
          border: 1px solid var(--border);
          border-radius: 999px;
          background: var(--bg);
          color: var(--text);
          text-decoration: none;
        }

        a:hover,
        a:focus-visible {
          border-color: var(--accent);
        }

        .is-inherited a {
          border-style: dashed;
          background: transparent;
        }

        .is-on_hold a,
        .is-dropped a {
          color: var(--muted);
        }
      }
    </style>
    <ul :if={@entries != []} class="tag-chips">
      <li
        :for={%{tag: tag, inherited: inherited} <- @entries}
        class={[inherited && "is-inherited", "is-#{tag.state}"]}
      >
        <.link
          navigate={~p"/tags/#{tag.id}"}
          title={chip_title(tag, inherited)}
          data-tag-id={tag.id}
        >
          <.path tag={tag} />
        </.link>
      </li>
    </ul>
    """
  end

  defp chip_title(tag, inherited) do
    [
      path_text(tag),
      inherited && "from the project",
      tag.state == :on_hold && "on hold",
      tag.state == :dropped && "dropped"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end
end
