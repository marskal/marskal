defmodule MarskalWeb.QuickCapture do
  @moduledoc """
  The phone's add button and the sheet behind it, which adds a task to the
  inbox from any page.
  """

  use MarskalWeb, :live_component

  alias Marskal.Tasks

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    {:ok, if(socket.assigns[:form], do: socket, else: reset(socket))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="quick-capture">
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.quick-capture) {
          .open {
            display: none;
          }

          dialog {
            width: 100%;
            max-width: 32rem;
            margin: auto auto 0;
            padding: 1rem 1rem calc(1rem + env(safe-area-inset-bottom));
            border: 0;
            border-radius: 12px 12px 0 0;
            background: var(--surface);
            color: var(--text);
          }

          dialog::backdrop {
            background: var(--scrim);
          }

          form {
            display: grid;
            grid-template-columns: minmax(0, 1fr) auto;
            gap: 0.5rem;
          }

          h2 {
            grid-column: 1 / -1;
            margin: 0 0 0.25rem;
            font-size: 1rem;
          }

          .close {
            position: absolute;
            top: 0.5rem;
            right: 0.5rem;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 2.75rem;
            height: 2.75rem;
            padding: 0;
            border: 0;
            background: transparent;
            color: var(--muted);
          }

          .error {
            grid-column: 1 / -1;
          }

          @media (max-width: 720px) {
            .open {
              display: inline-flex;
              align-items: center;
              justify-content: center;
              position: fixed;
              right: 1rem;
              bottom: calc(4.5rem + env(safe-area-inset-bottom));
              z-index: 15;
              width: 3.5rem;
              height: 3.5rem;
              padding: 0;
              border: 0;
              border-radius: 50%;
              background: var(--accent);
              color: var(--accent-contrast);
              box-shadow: 0 0.25rem 0.75rem var(--shadow);
            }

            .open .icon {
              width: 1.5rem;
              height: 1.5rem;
            }
          }
        }
      </style>

      <button type="button" class="open" aria-label="Add to inbox" aria-controls={"#{@id}-sheet"}>
        <Lucideicons.plus class="icon" />
      </button>

      <dialog
        id={"#{@id}-sheet"}
        aria-labelledby={"#{@id}-heading"}
        phx-mounted={JS.ignore_attributes("open")}
      >
        <button type="button" class="close" aria-label="Close">
          <Lucideicons.x class="icon" />
        </button>
        <.form for={@form} id={"#{@id}-form"} phx-submit="create" phx-target={@myself}>
          <input type="hidden" name="command_id" value={@command_id} />
          <h2 id={"#{@id}-heading"}><label for={"#{@id}-title"}>Add to inbox</label></h2>
          <input
            type="text"
            name={@form[:title].name}
            id={"#{@id}-title"}
            value={@form[:title].value}
            autocomplete="off"
            enterkeyhint="done"
            autofocus
            required
          />
          <button type="submit">Add</button>
          <p
            :for={msg <- Enum.map(@form[:title].errors, &translate_error/1)}
            class="error field-error"
          >
            {msg}
          </p>
        </.form>
      </dialog>
    </div>
    """
  end

  @impl true
  def handle_event("create", %{"task" => params, "command_id" => command_id}, socket) do
    case Tasks.create_task(socket.assigns.user, params, command_id) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> reset()
         |> flash(:info, "Added to the inbox.")
         |> push_event("quick-capture:added", %{id: "#{socket.assigns.id}-sheet"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "task"))}

      {:error, _reason} ->
        {:noreply, flash(socket, :error, "Could not add task.")}
    end
  end

  defp flash(socket, kind, message) do
    send(self(), {:put_flash, kind, message})
    socket
  end

  defp reset(socket) do
    socket
    |> assign(:command_id, Ecto.UUID.generate())
    |> assign(:form, to_form(%{"title" => ""}, as: "task"))
  end
end
