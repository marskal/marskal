defmodule MarskalWeb.SettingsComponents do
  @moduledoc """
  The settings sub-pages. Preferences change how the app behaves; Security
  holds the email, password, and devices, and needs a recent login. The
  two are separate live sessions, so a tab is a plain link.

  Fields look like the inspector's: a small muted label above the input,
  and a hint below it.
  """
  use MarskalWeb, :html

  attr :current, :atom, required: true, values: [:preferences, :security]
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.settings) {
        :scope {
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
          max-width: 36rem;
        }

        .tabs {
          display: flex;
          gap: 0.25rem;
          border-bottom: 1px solid var(--border);
        }

        .tabs a {
          padding: 0.5rem 0.85rem;
          margin-bottom: -1px;
          color: var(--muted);
          text-decoration: none;
          border-bottom: 2px solid transparent;
        }

        .tabs a:hover {
          color: var(--text);
        }

        .tabs a[aria-current="page"] {
          color: var(--text);
          border-bottom-color: var(--accent);
        }

        section {
          display: flex;
          flex-direction: column;
          gap: 0.85rem;
          padding: 1rem;
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }

        h2 {
          margin: 0;
          font-size: 0.95rem;
          font-weight: 600;
        }

        form {
          display: flex;
          flex-direction: column;
          gap: 0.85rem;
        }

        form:has(> section) {
          gap: 1.25rem;
        }

        form + form {
          padding-top: 0.85rem;
          border-top: 1px solid var(--border);
        }

        .fieldset {
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
        }

        .fieldset label {
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
          margin: 0;
          font-size: inherit;
        }

        .fieldset .label {
          font-size: 0.8rem;
          font-weight: 600;
          color: var(--muted);
        }

        /* .fieldset input matches app.css input[type="text"] on specificity,
           so the scoped rule wins. */
        .fieldset :is(input, select) {
          width: 100%;
          padding: 0.45rem 0.6rem;
          border: 1px solid var(--border-strong);
          border-radius: 6px;
          background: var(--bg);
          color: var(--text);
          font: inherit;
        }

        .fieldset p {
          display: flex;
          align-items: center;
          gap: 0.3rem;
          margin: 0;
          font-size: 0.8rem;
          color: var(--danger);
        }

        .fieldset:has(+ .hint) {
          margin-bottom: -0.55rem;
        }

        .hint {
          margin: 0;
          font-size: 0.8rem;
          color: var(--muted);
        }

        .actions {
          justify-content: flex-end;
        }

        .devices {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          margin: 0;
          padding: 0;
          list-style: none;
        }

        .devices li {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space);
          padding: 0.55rem 0.75rem;
          border: 1px solid var(--border);
          border-radius: 6px;
          background: var(--bg);
        }

        .devices li div {
          display: flex;
          flex-direction: column;
        }

        .devices .hint {
          font-size: 0.85rem;
        }
      }
    </style>
    <div class="settings">
      <.header>{gettext("Settings")}</.header>
      <nav class="tabs" id="settings-tabs" aria-label={gettext("Settings")}>
        <.link href={~p"/users/settings"} aria-current={@current == :preferences && "page"}>
          {gettext("Preferences")}
        </.link>
        <.link href={~p"/users/settings/security"} aria-current={@current == :security && "page"}>
          {gettext("Security")}
        </.link>
      </nav>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
