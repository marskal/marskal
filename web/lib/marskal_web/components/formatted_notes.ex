defmodule MarskalWeb.FormattedNotes do
  use MarskalWeb, :html

  attr :text, :string, default: nil
  attr :class, :string, default: "notes"

  def block(assigns) do
    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.notes) {
        :scope p,
        :scope ul,
        :scope ol {
          margin: 0 0 0.35rem;
        }

        :scope p:last-child,
        :scope ul:last-child,
        :scope ol:last-child {
          margin-bottom: 0;
        }

        :scope ul,
        :scope ol {
          padding-left: 1.25rem;
        }

        :scope a {
          color: var(--accent);
        }
      }
    </style>
    <div :if={is_binary(@text) and @text != ""} class={@class}>{raw(Marskal.Notes.html(@text))}</div>
    """
  end
end
