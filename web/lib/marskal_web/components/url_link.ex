defmodule MarskalWeb.UrlLink do
  @moduledoc "A task's or project's URL as a link that opens in a new tab (ADR 0022)."
  use MarskalWeb, :html

  attr :url, :string, default: nil
  attr :text, :boolean, default: false, doc: "show the URL beside the icon"

  def link(assigns) do
    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.url-link) {
        :scope {
          display: inline-flex;
          align-items: center;
          gap: 0.3rem;
          min-width: 0;
          max-width: 100%;
          color: var(--accent);
          vertical-align: middle;
        }

        .icon {
          flex: none;
          width: 0.95rem;
          height: 0.95rem;
        }

        .text {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }
    </style>
    <a
      :if={Marskal.Url.safe?(@url)}
      href={@url}
      class="url-link"
      target="_blank"
      rel="noopener noreferrer"
      title={@url}
      aria-label={if(!@text, do: "Open link")}
    >
      <Lucideicons.external_link class="icon" aria-hidden="true" />
      <span :if={@text} class="text">{@url}</span>
    </a>
    """
  end
end
