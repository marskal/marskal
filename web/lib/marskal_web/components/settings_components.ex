defmodule MarskalWeb.SettingsComponents do
  @moduledoc """
  The settings sub-pages. Preferences change how the app behaves; Security
  holds the email, password, and devices, and needs a recent login. The
  two are separate live sessions, so a tab is a plain link.
  """
  use MarskalWeb, :html

  attr :current, :atom, required: true, values: [:preferences, :security]

  def tabs(assigns) do
    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.settings-tabs) {
        :scope {
          display: flex;
          gap: 0.25rem;
          margin-bottom: var(--space);
          border-bottom: 1px solid var(--border);
        }

        a {
          padding: 0.5rem 0.85rem;
          margin-bottom: -1px;
          color: var(--muted);
          text-decoration: none;
          border-bottom: 2px solid transparent;
        }

        a:hover {
          color: inherit;
        }

        a[aria-current="page"] {
          color: inherit;
          border-bottom-color: currentColor;
        }
      }
    </style>
    <nav class="settings-tabs" id="settings-tabs" aria-label={gettext("Settings")}>
      <.link href={~p"/users/settings"} aria-current={@current == :preferences && "page"}>
        {gettext("Preferences")}
      </.link>
      <.link href={~p"/users/settings/security"} aria-current={@current == :security && "page"}>
        {gettext("Security")}
      </.link>
    </nav>
    """
  end
end
