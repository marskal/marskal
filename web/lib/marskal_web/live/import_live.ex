defmodule MarskalWeb.ImportLive do
  use MarskalWeb, :live_view

  alias Marskal.Imports

  @refresh_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, batch: nil, batches: [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_info(:refresh_import, socket) do
    user = socket.assigns.current_scope.user
    batch = socket.assigns.batch && Imports.get_batch(user, socket.assigns.batch.id)
    {:noreply, socket |> assign(:batch, batch) |> schedule_refresh()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style :type={MarskalWeb.ColocatedCSS}>
      @scope (.import-card) {
        :scope {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem 1rem;
          padding: 0.85rem 1rem;
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          text-decoration: none;
          color: inherit;
        }

        :scope:hover {
          border-color: var(--accent);
        }

        .source {
          font-weight: 600;
        }

        .status,
        .when {
          color: var(--muted);
          font-size: 0.9rem;
        }
      }

      @scope (.import-list) {
        :scope {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
          gap: 0.65rem;
        }
      }

      @scope (.import-stats) {
        :scope {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
          gap: 0.75rem;
          margin: 0 0 1.25rem;
        }

        div {
          padding: 0.75rem 0.85rem;
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }

        dt {
          color: var(--muted);
          font-size: 0.85rem;
        }

        dd {
          margin: 0.15rem 0 0;
          font-size: 1.25rem;
          font-weight: 600;
        }
      }

      @scope (.backup-drop) {
        :scope {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.5rem;
          margin-bottom: 1rem;
          padding: 1.5rem 1rem;
          border: 1px dashed var(--border);
          border-radius: var(--radius);
          background: var(--bg);
          text-align: center;
        }

        :scope.is-over {
          border-color: var(--accent);
          background: color-mix(in srgb, var(--accent) 10%, var(--bg));
        }

        .backup-drop__prompt {
          margin: 0;
          font-weight: 600;
        }

        .backup-drop__status {
          margin: 0;
          min-height: 1.25em;
          color: var(--muted);
          font-size: 0.9rem;
        }

        .backup-drop__actions {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
          justify-content: center;
        }
      }

      .backup-drop__hidden {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
      }
    </style>
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_nav={:import}
      inspector={assigns[:inspector]}
      inspector_refresh={assigns[:inspector_refresh]}
    >
      <%= cond do %>
        <% @live_action == :index -> %>
          <h1>Import</h1>
          <p class="lede">Bring a backup from another app into this account.</p>
          <p>
            <.link navigate={~p"/imports/new"} class="btn btn-primary">Upload an OmniFocus backup</.link>
          </p>
          <h2 :if={@batches != []}>Recent imports</h2>
          <ul :if={@batches != []} class="import-list">
            <li :for={batch <- @batches}>
              <.link navigate={~p"/imports/#{batch.id}"} class="import-card">
                <span class="source">{source_label(batch.source)}</span>
                <span class="status">{status_label(batch.status)}</span>
                <span class="when">{format_when(batch.inserted_at)}</span>
              </.link>
            </li>
          </ul>
          <p :if={@batches == []} class="empty">
            No imports yet. Start with an OmniFocus Backup Document.
          </p>
        <% @live_action == :new -> %>
          <p class="lede"><.link navigate={~p"/imports"}>Import</.link></p>
          <h1>OmniFocus backup</h1>
          <p class="lede">
            Drop the <code>.ofocus-backup</code>
            here. It looks like a file in Finder, but it is a folder.
            You can also choose a zip, or the <code>00000000000000=….zip</code>
            inside the package.
          </p>
          <form
            id="backup-drop"
            action={~p"/imports"}
            method="post"
            enctype="multipart/form-data"
            class="capture"
            phx-hook=".BackupDrop"
          >
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <div class="backup-drop" data-dropzone>
              <p class="backup-drop__prompt">Drop your OmniFocus backup here</p>
              <p class="backup-drop__status" data-status></p>
              <div class="backup-drop__actions">
                <button type="button" data-pick-file>Choose zip</button>
                <button type="button" data-pick-directory>Choose backup package</button>
              </div>
            </div>
            <input
              type="file"
              name="import_batch[payload]"
              accept=".ofocus-backup,.ofocus,.zip,application/zip"
              class="backup-drop__hidden"
              data-file
            />
            <input type="file" class="backup-drop__hidden" webkitdirectory directory data-directory />
            <button type="submit">Upload and preview</button>
          </form>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".BackupDrop">
            export default {
              mounted() {
                const form = this.el
                const dropzone = form.querySelector("[data-dropzone]")
                const status = form.querySelector("[data-status]")
                const fileInput = form.querySelector("[data-file]")
                const directoryInput = form.querySelector("[data-directory]")
                const setStatus = (text) => { if (status) status.textContent = text }

                form.querySelector("[data-pick-file]")?.addEventListener("click", () => fileInput?.click())
                form.querySelector("[data-pick-directory]")?.addEventListener("click", () => directoryInput?.click())

                fileInput?.addEventListener("change", () => {
                  const file = fileInput.files?.[0]
                  if (!file) return
                  setStatus(file.name)
                  form.requestSubmit()
                })

                directoryInput?.addEventListener("change", () => {
                  const files = Array.from(directoryInput.files || [])
                  if (!files.length) return
                  submitBundle(form, files.map((file) => ({
                    file,
                    path: file.webkitRelativePath || file.name
                  })), setStatus)
                })

                dropzone?.addEventListener("dragover", (event) => {
                  event.preventDefault()
                  dropzone.classList.add("is-over")
                })
                dropzone?.addEventListener("dragleave", (event) => {
                  if (event.target === dropzone) dropzone.classList.remove("is-over")
                })
                dropzone?.addEventListener("drop", async (event) => {
                  event.preventDefault()
                  dropzone.classList.remove("is-over")
                  const items = Array.from(event.dataTransfer?.items || [])
                  const entries = items.map((item) => item.webkitGetAsEntry?.()).filter(Boolean)
                  if (entries.length) {
                    const collected = []
                    for (const entry of entries) collected.push(...await collectEntry(entry, ""))
                    if (collected.length === 1 && isZip(collected[0].file)) {
                      assignFile(fileInput, collected[0].file)
                      setStatus(collected[0].file.name)
                      form.requestSubmit()
                      return
                    }
                    if (collected.length) {
                      await submitBundle(form, collected, setStatus)
                      return
                    }
                  }
                  const file = event.dataTransfer?.files?.[0]
                  if (file && fileInput) {
                    assignFile(fileInput, file)
                    setStatus(file.name)
                    form.requestSubmit()
                  }
                })
              }
            }

            function assignFile(input, file) {
              if (!input) return
              const transfer = new DataTransfer()
              transfer.items.add(file)
              input.files = transfer.files
            }

            async function submitBundle(form, collected, setStatus) {
              setStatus(`Reading ${collected.length} files from the backup…`)
              const body = new FormData()
              const token = form.querySelector("input[name='_csrf_token']")?.value
              if (token) body.append("_csrf_token", token)
              collected.forEach(({file, path}) => {
                body.append("import_batch[bundle_files][]", file, file.name)
                body.append("import_batch[bundle_paths][]", path)
              })
              const response = await fetch(form.action, {
                method: "POST",
                body,
                headers: {Accept: "text/html", "X-CSRF-Token": token || ""},
                redirect: "follow"
              })
              if (response.redirected) {
                window.location.assign(response.url)
                return
              }
              setStatus("Could not read that backup. Try dropping it again, or upload the zip inside the package.")
            }

            async function collectEntry(entry, prefix) {
              const path = prefix ? `${prefix}${entry.name}` : entry.name
              if (entry.isFile) {
                const file = await new Promise((resolve, reject) => entry.file(resolve, reject))
                return [{file, path}]
              }
              if (!entry.isDirectory) return []
              const children = await readDirectory(entry)
              const collected = []
              for (const child of children) collected.push(...await collectEntry(child, `${path}/`))
              return collected
            }

            function readDirectory(entry) {
              const reader = entry.createReader()
              const entries = []
              return new Promise((resolve, reject) => {
                const tick = () => {
                  reader.readEntries((batch) => {
                    if (!batch.length) {
                      resolve(entries)
                      return
                    }
                    entries.push(...batch)
                    tick()
                  }, reject)
                }
                tick()
              })
            }

            function isZip(file) {
              return /\.zip$/i.test(file.name) || /\.ofocus(-backup)?$/i.test(file.name)
            }
          </script>
        <% @live_action == :show && @batch -> %>
          <p class="lede"><.link navigate={~p"/imports"}>Import</.link></p>
          <h1>{source_label(@batch.source)} import</h1>
          <p class="lede">{@batch.filename || "Backup"} · {status_label(@batch.status)}</p>

          <div :if={@batch.status == :failed}>
            <p class="flash flash-error" role="alert">{@batch.error_message}</p>
            <p><.link navigate={~p"/imports/new"} class="btn">Try another file</.link></p>
          </div>
          <p :if={@batch.status == :pending} class="empty">Reading the backup…</p>
          <p :if={@batch.status == :applying} class="empty">Writing folders, projects, and tasks…</p>

          <div :if={@batch.status == :previewed}>
            <dl class="import-stats">
              <div>
                <dt>Folders</dt><dd>{stat(@batch, "folders")}</dd>
              </div>
              <div>
                <dt>Projects</dt><dd>{stat(@batch, "projects")}</dd>
              </div>
              <div>
                <dt>Tasks</dt><dd>{stat(@batch, "tasks")}</dd>
              </div>
              <div>
                <dt>Inbox</dt><dd>{stat(@batch, "inbox")}</dd>
              </div>
            </dl>
            <p :if={samples(@batch) != []} class="lede">
              Includes: {Enum.join(samples(@batch), ", ")}
            </p>
            <p class="lede">
              Already-imported OmniFocus items are skipped. Dates and tags are stored for later; they are not applied yet.
            </p>
            <form action={~p"/imports/#{@batch.id}/apply"} method="post">
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <button type="submit">Import into Marskal</button>
            </form>
          </div>

          <div :if={@batch.status == :applied}>
            <dl class="import-stats">
              <div>
                <dt>Created folders</dt><dd>{created(@batch, "folders")}</dd>
              </div>
              <div>
                <dt>Created projects</dt><dd>{created(@batch, "projects")}</dd>
              </div>
              <div>
                <dt>Created tasks</dt><dd>{created(@batch, "tasks")}</dd>
              </div>
              <div>
                <dt>Skipped</dt><dd>{skipped_total(@batch)}</dd>
              </div>
            </dl>
            <p class="actions">
              <.link navigate={~p"/inbox"} class="btn btn-primary">Inbox</.link>
              <.link navigate={~p"/"} class="btn">Open</.link>
            </p>
          </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp apply_action(socket, :index, _params) do
    user = socket.assigns.current_scope.user

    socket
    |> assign(:page_title, "Import")
    |> assign(:batches, Imports.list_batches(user))
    |> assign(:batch, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Upload backup")
    |> assign(:batches, [])
    |> assign(:batch, nil)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    user = socket.assigns.current_scope.user

    case Imports.get_batch(user, id) do
      nil ->
        socket
        |> put_flash(:error, "That import is not available.")
        |> redirect(to: ~p"/imports")

      batch ->
        socket
        |> assign(:page_title, "Import")
        |> assign(:batches, [])
        |> assign(:batch, batch)
        |> schedule_refresh()
    end
  end

  defp schedule_refresh(socket) do
    batch = socket.assigns.batch

    if (connected?(socket) and batch) && batch.status in [:pending, :applying] do
      Process.send_after(self(), :refresh_import, @refresh_ms)
    end

    socket
  end

  defp status_label(:pending), do: "Pending"
  defp status_label(:previewed), do: "Previewed"
  defp status_label(:applying), do: "Applying"
  defp status_label(:applied), do: "Applied"
  defp status_label(:failed), do: "Failed"
  defp status_label(other), do: to_string(other)

  defp source_label("omnifocus"), do: "OmniFocus"
  defp source_label(other), do: to_string(other)

  defp format_when(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  defp format_when(_datetime), do: ""

  defp stat(batch, key), do: (batch.stats || %{})[key] || 0
  defp created(batch, key), do: get_in(batch.stats || %{}, ["created", key]) || 0

  defp skipped_total(batch) do
    case (batch.stats || %{})["skipped"] do
      %{} = skipped -> skipped |> Map.values() |> Enum.sum()
      _ -> 0
    end
  end

  defp samples(batch) do
    case (batch.stats || %{})["samples"] do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      _ -> []
    end
  end
end
