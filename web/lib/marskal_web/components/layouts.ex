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
  attr :current_id, :string, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assign(
        assigns,
        :nav,
        if(assigns.current_scope && assigns.current_scope.user,
          do: Marskal.ProjectNav.build(assigns.current_scope.user)
        )
      )

    ~H"""
    <div class="app">
      <header class="app-header">
        <div class="app-header__brand">
          <.link navigate={~p"/"}>Marskal</.link>
        </div>
        <div class="app-header__account">
          <%= if @current_scope && @current_scope.user do %>
            <span class="who">{@current_scope.user.email}</span>
            <.link :if={@current_scope.user.superuser} href={~p"/dev/dashboard"}>Dashboard</.link>
            <.link href={~p"/users/settings"}>Settings</.link>
            <.link href={~p"/users/log-out"} method="delete">Log out</.link>
          <% else %>
            <.link href={~p"/users/log-in"}>Log in</.link>
            <.link href={~p"/users/register"}>Register</.link>
          <% end %>
        </div>
      </header>

      <div class="app-body">
        <MarskalWeb.NavComponents.sidebar
          :if={@nav}
          nav={@nav}
          user={@current_scope.user}
          current_nav={@current_nav}
          current_id={@current_id}
        />
        <main class="app-main">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

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
        <Lucideicons.loader_circle class="icon icon-spin" />
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
        <Lucideicons.loader_circle class="icon icon-spin" />
      </.flash>
    </div>
    """
  end
end
