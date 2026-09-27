defmodule MarskalWeb.TagLive do
  use MarskalWeb, :live_view

  alias Marskal.Tags
  alias Marskal.Tags.Tree
  alias Marskal.Tasks
  alias MarskalWeb.TagComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Tags.get_tag(user, id) do
      nil ->
        {:ok, socket |> put_flash(:error, "That tag is not available.") |> redirect(to: ~p"/")}

      tag ->
        {:ok, socket |> assign(:tag_id, tag.id) |> new_tag_form() |> load()}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_id={@tag.id}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <p :if={@ancestors != []} class="lede tag-ancestors">
        <%= for {ancestor, i} <- Enum.with_index(@ancestors) do %>
          <span :if={i > 0} aria-hidden="true">›</span>
          <.link navigate={~p"/tags/#{ancestor.id}"}>{ancestor.name}</.link>
        <% end %>
      </p>
      <h1>{@tag.name}</h1>
      <p :if={state_note(@tag, @state)} class="lede">{state_note(@tag, @state)}</p>
      <p class="actions">
        <button :if={@tag.state != :on_hold} type="button" phx-click="state" phx-value-state="on_hold">
          Put on hold
        </button>
        <button :if={@tag.state != :dropped} type="button" phx-click="state" phx-value-state="dropped">
          Drop
        </button>
        <button :if={@tag.state != :active} type="button" phx-click="state" phx-value-state="active">
          Activate
        </button>
      </p>

      <.outline_node
        node={@outline.root}
        root_id={@tag.id}
        task_tags={@task_tags}
        inspector={@inspector}
      />

      <.form for={@tag_form} id="new-child-tag" phx-submit="create-tag" class="capture">
        <input type="hidden" name="command_id" value={@tag_command_id} />
        <label for={@tag_form[:name].id}>New tag inside</label>
        <input type="text" name={@tag_form[:name].name} id={@tag_form[:name].id} required />
        <button type="submit">Add tag</button>
      </.form>
    </Layouts.app>
    """
  end

  attr :node, :map, required: true
  attr :root_id, :string, required: true
  attr :task_tags, :map, required: true
  attr :inspector, :any, default: nil

  # The tag's own tasks, then one section per child tag, nested the same
  # way (ADR 0005).
  defp outline_node(assigns) do
    ~H"""
    <section class="tag-group" id={"tag-group-#{@node.tag.id}"}>
      <h2 :if={@node.tag.id != @root_id}>
        <.link navigate={~p"/tags/#{@node.tag.id}"}>{@node.tag.name}</.link>
      </h2>
      <MarskalWeb.TaskComponents.list
        :if={@node.tasks != [] or @node.tag.id == @root_id}
        id={"tag-tasks-#{@node.tag.id}"}
        tasks={@node.tasks}
        tags={@task_tags.tags}
        unavailable={@task_tags.unavailable}
        mark_inbox
        empty="No tasks carry this tag itself."
        actions={[:complete]}
        inspector={@inspector}
      />
      <.outline_node
        :for={child <- @node.children}
        node={child}
        root_id={@root_id}
        task_tags={@task_tags}
        inspector={@inspector}
      />
    </section>
    """
  end

  @impl true
  def handle_info({:marskal_change, _type, _id}, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("complete", %{"id" => id}, socket), do: act(socket, id, &Tasks.complete_task/3)
  def handle_event("reopen", %{"id" => id}, socket), do: act(socket, id, &Tasks.reopen_task/3)

  def handle_event("state", %{"state" => state}, socket)
      when state in ["active", "on_hold", "dropped"] do
    user = socket.assigns.current_scope.user

    case Tags.set_tag_state(user, socket.assigns.tag.id, state, Ecto.UUID.generate()) do
      {:ok, _tag} -> {:noreply, load(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update tag.")}
    end
  end

  def handle_event("create-tag", %{"tag" => params, "command_id" => command_id}, socket) do
    user = socket.assigns.current_scope.user
    attrs = Map.put(params, "parent_id", socket.assigns.tag.id)

    case Tags.create_tag(user, attrs, command_id) do
      {:ok, _tag} ->
        {:noreply, socket |> new_tag_form() |> load()}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "A tag with that name is already here.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add tag.")}
    end
  end

  defp act(socket, id, fun) do
    case fun.(socket.assigns.current_scope.user, id, Ecto.UUID.generate()) do
      {:ok, _task} -> {:noreply, load(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update task.")}
    end
  end

  # A deleted tag, or one merged away, leaves the page.
  defp load(socket) do
    user = socket.assigns.current_scope.user

    case Tags.outline(user, socket.assigns.tag_id) do
      nil ->
        socket |> put_flash(:info, "That tag was deleted.") |> push_navigate(to: ~p"/")

      %{root: root, tree: tree} = outline ->
        socket
        |> assign(:page_title, TagComponents.path_text(root.tag))
        |> assign(:tag, root.tag)
        |> assign(:state, Tree.state(tree, root.tag.id) || root.tag.state)
        |> assign(:ancestors, ancestors(tree, root.tag))
        |> assign(:outline, outline)
        |> assign(:task_tags, %{tags: outline.effective, unavailable: outline.unavailable})
    end
  end

  defp ancestors(tree, tag) do
    case tag.parent_id && Tree.get(tree, tag.parent_id) do
      nil -> []
      parent -> ancestors(tree, parent) ++ [parent]
    end
  end

  defp new_tag_form(socket) do
    socket
    |> assign(:tag_command_id, Ecto.UUID.generate())
    |> assign(:tag_form, to_form(%{"name" => ""}, as: "tag"))
  end

  defp state_note(%{state: :on_hold}, _state),
    do: "On hold. Tasks with this tag are unavailable."

  defp state_note(%{state: :dropped}, _state),
    do: "Dropped. This tag and the tags inside it are hidden from lists."

  defp state_note(_tag, :dropped),
    do: "Inside a dropped tag, so it is hidden from lists."

  defp state_note(_tag, _state), do: nil
end
