defmodule MarskalWeb.FormattedNotes do
  @moduledoc """
  Renders a task or project's notes.
  """

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

        /* A wide table scrolls inside its own box instead of widening the
           row or pane it sits in. */
        :scope table {
          display: block;
          max-width: 100%;
          overflow-x: auto;
          margin: 0 0 0.35rem;
          border-collapse: collapse;
          font-size: 0.9em;
        }

        :scope table:last-child {
          margin-bottom: 0;
        }

        :scope :is(th, td) {
          padding: 0.25rem 0.6rem;
          border: 1px solid var(--border);
          vertical-align: top;
        }

        :scope th {
          background: color-mix(in srgb, var(--text) 7%, transparent);
          font-weight: 600;
          text-align: left;
        }

        :scope tbody tr:nth-child(even) {
          background: color-mix(in srgb, var(--text) 3%, transparent);
        }

        :scope th[align="center"] {
          text-align: center;
        }

        :scope th[align="right"] {
          text-align: right;
        }

        :scope :is(code, pre) {
          font-family: var(--font-mono);
          font-size: 0.9em;
        }

        :scope pre {
          margin: 0 0 0.35rem;
          overflow-x: auto;
          line-height: 1.25;
        }

        :scope pre:last-child {
          margin-bottom: 0;
        }
      }
    </style>
    <div :if={is_binary(@text) and @text != ""} class={@class}>{raw(Marskal.Notes.html(@text))}</div>
    """
  end
end
