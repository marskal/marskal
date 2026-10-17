defmodule MarskalWeb.UserLive.CheckEmail do
  @moduledoc """
  Where a step that emails a link lands: registering, signing in to an
  unconfirmed account, and asking for a password reset. It says only to
  open the email, since there is nothing to do here until then. The flash
  carries which step (`:check_email`) and the address (`:email`); without
  them, as after a reload, it goes to log in.
  """

  use MarskalWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} inspector={assigns[:inspector]}>
      <h1>{gettext("Check your email")}</h1>
      <%= case @kind do %>
        <% "registered" -> %>
          <p class="lede">
            {gettext("We've sent a link to %{email}. Open it to confirm your account.",
              email: @email
            )}
          </p>
          <p>{gettext("The link works for 7 days.")}</p>
        <% "unconfirmed" -> %>
          <p class="lede">
            {gettext("Your account isn't confirmed yet. Open the link we sent to %{email}.",
              email: @email
            )}
          </p>
          <p>{gettext("The link works for 7 days.")}</p>
        <% "reset_password" -> %>
          <p class="lede">
            {gettext("If %{email} has an account, we've sent it a link to choose a new password.",
              email: @email
            )}
          </p>
          <p>{gettext("The link works for an hour.")}</p>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    kind = Phoenix.Flash.get(socket.assigns.flash, :check_email)
    email = Phoenix.Flash.get(socket.assigns.flash, :email)

    if kind in ["registered", "unconfirmed", "reset_password"] and is_binary(email) do
      {:ok, assign(socket, kind: kind, email: email)}
    else
      {:ok, push_navigate(socket, to: ~p"/users/log-in")}
    end
  end

  @doc "Sends a socket or conn here, saying `kind` about `email`."
  def put_flash_for(conn_or_socket, kind, email) do
    conn_or_socket
    |> put_flash_any(:check_email, kind)
    |> put_flash_any(:email, String.slice(email, 0, 160))
  end

  defp put_flash_any(%Plug.Conn{} = conn, key, value),
    do: Phoenix.Controller.put_flash(conn, key, value)

  defp put_flash_any(socket, key, value), do: Phoenix.LiveView.put_flash(socket, key, value)
end
