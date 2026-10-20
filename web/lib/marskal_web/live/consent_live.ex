defmodule MarskalWeb.ConsentLive do
  @moduledoc """
  Hydra's consent UI (ADR 0021). It shows which program asks for what, and
  asks for a name for the device, since the device grant carries none.
  Allowing records the device and grants the scopes; both happen on a
  LiveView event, never on the page load.
  """

  use MarskalWeb, :live_view

  alias Marskal.Devices
  alias Marskal.Hydra

  @scopes %{
    "sync:read" => "Read your tasks, projects, folders, and tags",
    "sync:write" => "Add and change your tasks, projects, folders, and tags",
    "offline_access" => "Stay signed in until you sign it out"
  }

  @doc "What a scope allows, in words."
  def describe_scope(scope), do: Map.get(@scopes, scope, scope)

  @impl true
  def mount(%{"consent_challenge" => challenge}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Hydra.get_consent_request(challenge) do
      {:ok, %{"subject" => subject} = request} when subject == user.id ->
        client = request["client"] || %{}

        today =
          user
          |> Marskal.Accounts.timezone()
          |> Marskal.Dates.today()
          |> Marskal.DateFormat.date(:day_month_year)

        {:ok,
         assign(socket,
           challenge: challenge,
           request: request,
           client_name: client["client_name"] || client["client_id"] || "A program",
           scopes: request["requested_scope"] || [],
           form: to_form(%{"name" => "#{client["client_name"] || "Device"}, #{today}"})
         )}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/oauth/error?#{[error: "consent_failed"]}")}
    end
  end

  def mount(_params, _session, socket),
    do: {:ok, push_navigate(socket, to: ~p"/oauth/error?#{[error: "invalid_request"]}")}

  @impl true
  def handle_event("allow", %{"name" => name}, socket) do
    %{challenge: challenge, request: request, scopes: scopes} = socket.assigns
    user = socket.assigns.current_scope.user

    attrs = %{
      name: name,
      client_id: get_in(request, ["client", "client_id"]) || "unknown",
      consent_request_id: request["consent_request_id"]
    }

    with {:ok, device} <- Devices.create(user, attrs),
         {:ok, url} <- accept(device, challenge, scopes) do
      {:noreply, redirect(socket, external: url)}
    else
      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         socket
         |> assign(form: to_form(%{"name" => name}))
         |> put_flash(:error, "Give the device a name, of at most 100 characters.")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The sign-in could not be finished. Start again on the device."
         )}
    end
  end

  def handle_event("deny", _params, socket) do
    case Hydra.reject_consent(socket.assigns.challenge) do
      {:ok, url} ->
        {:noreply, redirect(socket, external: url)}

      {:error, _} ->
        {:noreply, push_navigate(socket, to: ~p"/oauth/error?#{[error: "access_denied"]}")}
    end
  end

  @impl true
  def handle_info({:marskal_change, _type, _id}, socket), do: {:noreply, socket}

  defp accept(device, challenge, scopes) do
    case Hydra.accept_consent(challenge, scopes, device.id) do
      {:ok, url} ->
        {:ok, url}

      error ->
        Devices.discard_unconsented(device)
        error
    end
  end

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
        @scope (.consent) {
          :scope {
            max-width: 28rem;
            display: flex;
            flex-direction: column;
            gap: var(--space);
          }

          .scopes {
            margin: 0;
            padding-left: 1.25rem;
          }

          .deny {
            background: transparent;
            color: var(--danger);
            border-color: var(--danger);
          }
        }
      </style>

      <section class="consent">
        <.header>Allow {@client_name}?</.header>
        <p>On this device, {@client_name} will be able to:</p>
        <ul class="scopes">
          <li :for={scope <- @scopes}>{describe_scope(scope)}</li>
        </ul>

        <.form for={@form} id="consent-form" phx-submit="allow">
          <.input field={@form[:name]} label="Name this device" maxlength="100" required />
          <div class="actions">
            <.button variant="primary">Allow</.button>
            <button type="button" class="btn deny" phx-click="deny">Deny</button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
