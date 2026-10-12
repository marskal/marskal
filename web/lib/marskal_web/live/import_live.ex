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

  def handle_info({:marskal_change, _type, _id}, socket), do: {:noreply, socket}

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

      @scope (.import-kept) {
        :scope ul {
          margin: 0 0 1.25rem;
          padding-left: 1.25rem;
        }

        .fields {
          color: var(--muted);
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
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <%= cond do %>
        <% @live_action == :index -> %>
          <h1>Import</h1>
          <p class="lede">Bring tasks in from Todoist, or from an OmniFocus backup.</p>
          <p class="actions">
            <.link href={~p"/imports/todoist"} class="btn btn-primary">Import from Todoist</.link>
            <.link navigate={~p"/imports/new"} class="btn">Upload an OmniFocus backup</.link>
          </p>
          <h2 :if={@batches != []}>Recent imports</h2>
          <ul :if={@batches != []} class="import-list">
            <li :for={batch <- @batches}>
              <.link navigate={~p"/imports/#{batch.id}"} class="import-card">
                <span class="source">{source_label(batch.source)}</span>
                <span class="status">{status_label(batch.status)}</span>
                <span class="when">{format_when(batch.inserted_at, @current_scope.user)}</span>
              </.link>
            </li>
          </ul>
          <p :if={@batches == []} class="empty">
            No imports yet. Import from Todoist, or upload an OmniFocus Backup Document.
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
          <script :type={Phoenix.LiveView.ColocatedHook} name=".BackupDrop" extension="ts">
            import {ViewHook} from "phoenix_live_view"

            type Collected = {file: File; path: string}
            type SetStatus = (text: string) => void

            export default class extends ViewHook<HTMLFormElement> {
              mounted() {
                const form = this.el
                const dropzone = form.querySelector<HTMLElement>("[data-dropzone]")
                const status = form.querySelector("[data-status]")
                const fileInput = form.querySelector<HTMLInputElement>("[data-file]")
                const directoryInput = form.querySelector<HTMLInputElement>("[data-directory]")
                const setStatus: SetStatus = (text) => { if (status) status.textContent = text }

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
                  const entries = items
                    .map((item) => item.webkitGetAsEntry?.())
                    .filter((entry): entry is FileSystemEntry => !!entry)
                  if (entries.length) {
                    const collected: Collected[] = []
                    for (const entry of entries) collected.push(...await collectEntry(entry, ""))
                    const [only] = collected
                    if (collected.length === 1 && only && isZip(only.file)) {
                      assignFile(fileInput, only.file)
                      setStatus(only.file.name)
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

            function assignFile(input: HTMLInputElement | null, file: File) {
              if (!input) return
              const transfer = new DataTransfer()
              transfer.items.add(file)
              input.files = transfer.files
            }

            async function submitBundle(form: HTMLFormElement, collected: Collected[], setStatus: SetStatus) {
              setStatus(`Reading ${collected.length} files from the backup…`)
              const body = new FormData()
              const token = form.querySelector<HTMLInputElement>("input[name='_csrf_token']")?.value
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

            async function collectEntry(entry: FileSystemEntry, prefix: string): Promise<Collected[]> {
              const path = prefix ? `${prefix}${entry.name}` : entry.name
              if (isFile(entry)) {
                const file = await new Promise<File>((resolve, reject) => entry.file(resolve, reject))
                return [{file, path}]
              }
              if (!isDirectory(entry)) return []
              const children = await readDirectory(entry)
              const collected: Collected[] = []
              for (const child of children) collected.push(...await collectEntry(child, `${path}/`))
              return collected
            }

            function readDirectory(entry: FileSystemDirectoryEntry): Promise<FileSystemEntry[]> {
              const reader = entry.createReader()
              const entries: FileSystemEntry[] = []
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

            function isFile(entry: FileSystemEntry): entry is FileSystemFileEntry {
              return entry.isFile
            }

            function isDirectory(entry: FileSystemEntry): entry is FileSystemDirectoryEntry {
              return entry.isDirectory
            }

            function isZip(file: File) {
              return /\.zip$/i.test(file.name) || /\.ofocus(-backup)?$/i.test(file.name)
            }
          </script>
        <% @live_action == :show && @batch -> %>
          <p class="lede"><.link navigate={~p"/imports"}>Import</.link></p>
          <h1>{source_label(@batch.source)} import</h1>
          <p class="lede">
            {@batch.external_account || @batch.filename || "Backup"} · {status_label(@batch.status)}
          </p>

          <div :if={@batch.status in [:failed, :expired]}>
            <p class="flash flash-error" role="alert">{@batch.error_message}</p>
            <p :if={@batch.source == "todoist"}>
              <.link href={~p"/imports/todoist"} class="btn">Try Todoist again</.link>
            </p>
            <p :if={@batch.source != "todoist"}>
              <.link navigate={~p"/imports/new"} class="btn">Try another file</.link>
            </p>
          </div>
          <p :if={@batch.status == :pending} class="empty">{reading_label(@batch)}</p>
          <p :if={@batch.status == :applying} class="empty">
            Writing tags, folders, projects, and tasks…
          </p>

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
              <div>
                <dt>Tags</dt><dd>{stat(@batch, "tags")}</dd>
              </div>
            </dl>
            <p :if={samples(@batch) != []} class="lede">
              Includes: {Enum.join(samples(@batch), ", ")}
            </p>
            <.import_problems batch={@batch} />
            <p class="lede">{preview_note(@batch)}</p>
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
                <dt>Created tags</dt><dd>{created(@batch, "tags")}</dd>
              </div>
              <div>
                <dt>Updated</dt><dd>{total(@batch, "updated")}</dd>
              </div>
              <div>
                <dt>Kept your edits</dt><dd>{stat(@batch, "kept")}</dd>
              </div>
              <div>
                <dt>Unchanged</dt><dd>{total(@batch, "skipped")}</dd>
              </div>
            </dl>
            <p :if={stat(@batch, "recreated") > 0} class="lede" id="import-recreated">
              {stat(@batch, "recreated")} you had deleted here came back as new items, since {source_label(
                @batch.source
              )} still has them.
            </p>
            <.import_problems batch={@batch} />
            <div :if={kept_samples(@batch) != []} id="import-kept" class="import-kept">
              <p class="lede">
                Changed in {source_label(@batch.source)} and by you. Your version stays:
              </p>
              <ul>
                <li :for={sample <- kept_samples(@batch)}>
                  {sample["title"]} <span class="fields">({Enum.join(sample["fields"], ", ")})</span>
                </li>
              </ul>
            </div>
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
  defp status_label(:expired), do: "Expired"
  defp status_label(other), do: to_string(other)

  defp source_label("omnifocus"), do: "OmniFocus"
  defp source_label("todoist"), do: "Todoist"
  defp source_label(other), do: to_string(other)

  defp reading_label(%{source: "todoist"}), do: "Reading your Todoist account…"
  defp reading_label(_batch), do: "Reading the backup…"

  defp preview_note(%{source: "todoist"}) do
    "Already-imported items are updated with what changed in Todoist, except where you changed the same thing here. Items you deleted here come back. Labels become tags. Sections and recurrence cannot be brought over yet; those tasks are tagged Import problems. Completed history is not included."
  end

  defp preview_note(_batch) do
    "Already-imported items are updated with what changed in OmniFocus, except where you changed the same thing here. Items you deleted here come back. Tags whose name is already used at the same place are reused."
  end

  attr :batch, :map, required: true

  # What did not fit: items carry a tag and a note; folders can do neither.
  defp import_problems(assigns) do
    ~H"""
    <p :if={stat(@batch, "problems") > 0} class="lede" id="import-problems">
      {stat(@batch, "problems")} {if stat(@batch, "problems") == 1, do: "item", else: "items"} could not be brought over in full. They are tagged Import problems, and their notes end with what is missing.
    </p>
    <div :if={folder_problems(@batch) != []} id="import-folder-problems" class="import-kept">
      <p class="lede">Folders cannot hold these, so they are left out:</p>
      <ul>
        <li :for={folder <- folder_problems(@batch)}>
          {folder["name"]} <span class="fields">({Enum.join(folder["fields"], ", ")})</span>
        </li>
      </ul>
    </div>
    """
  end

  defp folder_problems(batch) do
    case (batch.stats || %{})["folder_problems"] do
      list when is_list(list) ->
        Enum.filter(list, &match?(%{"name" => _, "fields" => [_ | _]}, &1))

      _ ->
        []
    end
  end

  defp format_when(%DateTime{} = datetime, user) do
    datetime
    |> DateTime.shift_zone!(Marskal.Accounts.timezone(user))
    |> Marskal.DateFormat.date_time()
  end

  defp format_when(_datetime, _user), do: ""

  defp stat(batch, key), do: (batch.stats || %{})[key] || 0
  defp created(batch, key), do: get_in(batch.stats || %{}, ["created", key]) || 0

  defp total(batch, key) do
    case (batch.stats || %{})[key] do
      %{} = counts -> counts |> Map.values() |> Enum.sum()
      _ -> 0
    end
  end

  defp kept_samples(batch) do
    case (batch.stats || %{})["kept_samples"] do
      list when is_list(list) ->
        Enum.filter(list, &match?(%{"title" => _, "fields" => [_ | _]}, &1))

      _ ->
        []
    end
  end

  defp samples(batch) do
    case (batch.stats || %{})["samples"] do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      _ -> []
    end
  end
end
