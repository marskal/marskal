defmodule MarskalWeb.DeviceLive do
  @moduledoc """
  Hydra's device verification UI, its success page, and its error page
  (ADR 0021). A device shows a code and sends the user to Hydra, which sends
  them here with a `device_challenge`. Confirming the code is a LiveView
  event, never the page load, so it cannot be forged by a link.
  """

  use MarskalWeb, :live_view

  alias Marskal.Hydra

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       challenge: params["device_challenge"],
       form: to_form(%{"user_code" => params["user_code"] || ""})
     )}
  end

  @impl true
  def handle_params(params, _uri, %{assigns: %{live_action: :verify}} = socket) do
    # Without a challenge, start at Hydra, which makes one.
    if params["device_challenge"] in [nil, ""] do
      query =
        if params["user_code"],
          do: "?" <> URI.encode_query(user_code: params["user_code"]),
          else: ""

      {:noreply,
       redirect(socket, external: Hydra.public_url() <> "/oauth2/device/verify" <> query)}
    else
      {:noreply, socket}
    end
  end

  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, error: params["error_description"] || params["error"])}

  @impl true
  def handle_event("confirm", %{"user_code" => code}, socket) do
    case Hydra.accept_user_code(socket.assigns.challenge, normalize(code)) do
      {:ok, url} ->
        {:noreply, redirect(socket, external: url)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(form: to_form(%{"user_code" => code}))
         |> put_flash(
           :error,
           "That code is not right, or it has expired. Check it, or start again on the device."
         )}
    end
  end

  @impl true
  def handle_info({:marskal_change, _type, _id}, socket), do: {:noreply, socket}

  # Codes are shown as XXXX-XXXX and typed any way.
  defp normalize(code), do: code |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
      visibility={assigns[:visibility]}
    >
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.device-sign-in) {
          :scope {
            max-width: 28rem;
            display: flex;
            flex-direction: column;
            gap: var(--space);
          }

          .code {
            font-family: ui-monospace, monospace;
            font-size: 1.4rem;
            letter-spacing: 0.15em;
            text-transform: uppercase;
          }

          .muted {
            color: var(--muted);
          }
        }
      </style>

      <section class="device-sign-in">
        <%= case @live_action do %>
          <% :verify -> %>
            <.header>
              Sign in a device
              <:subtitle>Type the code your device shows.</:subtitle>
            </.header>

            <.form for={@form} id="user-code-form" phx-submit="confirm">
              <.input
                field={@form[:user_code]}
                label="Code"
                class="code"
                autocomplete="off"
                autocapitalize="characters"
                spellcheck="false"
                required
              />
              <p class="muted">
                Only continue if you started signing in on that device, and it shows this code.
              </p>
              <.button variant="primary">Continue</.button>
            </.form>
          <% :done -> %>
            <.header>Signed in</.header>
            <p id="device-done">You can go back to your device.</p>
            <p class="muted">
              Sign it out any time from <.link href={~p"/users/settings/security"}>settings</.link>.
            </p>
          <% :error -> %>
            <.header>The device was not signed in</.header>
            <p id="device-error">{@error || "Something went wrong."}</p>
            <p class="muted">Start signing in again on the device.</p>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
