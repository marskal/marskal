defmodule MarskalWeb.TagLive do
  use MarskalWeb, :live_view
  use MarskalWeb.TaskActions, reload: &load/1

  alias Marskal.Tags
  alias Marskal.Tags.Tree
  alias Marskal.Tasks
  alias MarskalWeb.TagComponents
  alias MarskalWeb.TaskList

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
      <MarskalWeb.NavComponents.page_heading type={:tag} id={@tag.id} inspector={@inspector}>
        {@tag.name}
      </MarskalWeb.NavComponents.page_heading>
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
        zone={Marskal.Accounts.timezone(@current_scope.user)}
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
  attr :zone, :string, required: true
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
        deferred={@task_tags.deferred}
        dates={@task_tags.dates}
        resolved={@task_tags.resolved}
        parents={@task_tags.parents}
        repeating={@task_tags.repeating}
        flagged={@task_tags.flagged}
        zone={@zone}
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
        zone={@zone}
      />
    </section>
    """
  end

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

  # A deleted tag, or one merged away, leaves the page.
  defp load(socket) do
    user = socket.assigns.current_scope.user

    case Tags.outline(user, socket.assigns.tag_id) do
      nil ->
        socket |> put_flash(:info, "That tag was deleted.") |> push_navigate(to: ~p"/")

      %{root: root, tree: tree} = outline ->
        outline = keep_rows(user, socket.assigns[:outline], outline)

        socket
        |> assign(:page_title, TagComponents.path_text(root.tag))
        |> assign(:tag, root.tag)
        |> assign(:state, Tree.state(tree, root.tag.id) || root.tag.state)
        |> assign(:ancestors, ancestors(tree, root.tag))
        |> assign(:outline, outline)
        |> assign(:task_tags, annotate(user, outline))
    end
  end

  # The outline already has the tag annotations; the rest are per task.
  defp annotate(user, outline) do
    tasks = node_tasks(outline.root)

    %{
      tags: outline.effective,
      unavailable: outline.unavailable,
      deferred: Tasks.deferred_ids(user, tasks),
      dates: Tasks.effective_dates(user, tasks),
      resolved: Tasks.resolved_ids(user, Enum.map(tasks, & &1.id)),
      parents: TaskList.parents(user, tasks),
      repeating: Marskal.Recurrence.repeating_ids(user, tasks),
      flagged: Tasks.flagged_ids(user, tasks)
    }
  end

  # Done and dropped tasks stay in their groups until the user leaves
  # the page (see `MarskalWeb.TaskList`). A group they would empty stays too.
  defp keep_rows(_user, nil, outline), do: outline

  defp keep_rows(user, old, outline) do
    case TaskList.lingering(user, node_tasks(old.root), node_tasks(outline.root)) do
      lingering when lingering == %{} ->
        outline

      lingering ->
        kept = Tags.annotate(user, Map.values(lingering))

        %{
          outline
          | root: merge_node(old.root, outline.root, lingering),
            effective: Map.merge(outline.effective, kept.tags),
            unavailable: MapSet.union(outline.unavailable, kept.unavailable)
        }
    end
  end

  defp merge_node(old, node, lingering) do
    old_children = Map.new(old.children, &{&1.tag.id, &1})
    ids = MapSet.new(node.children, & &1.tag.id)

    children =
      Enum.map(node.children, fn child ->
        case old_children[child.tag.id] do
          nil -> child
          old_child -> merge_node(old_child, child, lingering)
        end
      end)

    gone =
      for old_child <- old.children,
          old_child.tag.id not in ids,
          kept = merge_node(old_child, %{old_child | tasks: [], children: []}, lingering),
          node_tasks(kept) != [],
          into: %{},
          do: {old_child.tag.id, kept}

    %{
      node
      | tasks: TaskList.merge(old.tasks, node.tasks, lingering),
        children: TaskList.merge(old.children, children, gone, & &1.tag.id)
    }
  end

  defp node_tasks(node), do: node.tasks ++ Enum.flat_map(node.children, &node_tasks/1)

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
