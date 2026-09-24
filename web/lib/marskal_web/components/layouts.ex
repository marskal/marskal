defmodule MarskalWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MarskalWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_nav, :atom, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="app">
      <header class="app-header">
        <div class="app-header__brand">
          <.link navigate={~p"/"}>Marskal</.link>
        </div>
        <nav class="app-nav" :if={@current_scope && @current_scope.user}>
          <.link navigate={~p"/inbox"} class={nav_class(@current_nav, :inbox)}>Inbox</.link>
          <.link navigate={~p"/"} class={nav_class(@current_nav, :open)}>Open</.link>
        </nav>
        <div class="app-header__account">
          <%= if @current_scope && @current_scope.user do %>
            <span class="who">{@current_scope.user.email}</span>
            <.link href={~p"/users/settings"}>Settings</.link>
            <.link href={~p"/users/log-out"} method="delete">Log out</.link>
          <% else %>
            <.link href={~p"/users/log-in"}>Log in</.link>
            <.link href={~p"/users/register"}>Register</.link>
          <% end %>
        </div>
      </header>

      <main class="app-main">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp nav_class(current, name) when current == name, do: "is-current"
  defp nav_class(_current, _name), do: nil

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
