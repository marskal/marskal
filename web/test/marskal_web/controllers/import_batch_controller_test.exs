defmodule MarskalWeb.ImportBatchControllerTest do
  use MarskalWeb.ConnCase, async: true

  import Ecto.Query
  import Marskal.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Marskal.ImportBatch
  alias Marskal.Imports
  alias Marskal.Imports.ApplyJob
  alias Marskal.Imports.Limits
  alias Marskal.Imports.ParseJob
  alias Marskal.Imports.Todoist
  alias Marskal.Repo
  alias Marskal.Tasks.Task

  use Oban.Testing, repo: Marskal.Repo

  setup :register_and_log_in_user

  test "index requires sign in" do
    conn = build_conn() |> get(~p"/imports")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "import page offers todoist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/imports")
    assert html =~ "Import from Todoist"
    assert html =~ "/imports/todoist"
    assert html =~ "Upload a TaskPaper file"
    assert html =~ "/exports/taskpaper"
    {:ok, _view, html} = live(conn, ~p"/imports/taskpaper")
    assert html =~ "A project ends with a colon"
  end

  test "todoist sign-in stores a snapshot and previews it", %{conn: conn, user: user} do
    Req.Test.stub(Todoist, fn conn ->
      case conn.request_path do
        "/oauth/access_token" ->
          Req.Test.json(conn, %{"access_token" => "token-1", "refresh_token" => "do-not-store"})

        "/api/v1/sync" ->
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token-1"]
          Req.Test.json(conn, TodoistSnapshot.small())

        other ->
          flunk("unexpected Todoist request #{other}")
      end
    end)

    conn = get(conn, ~p"/imports/todoist")
    assert redirected_to(conn) =~ "https://app.todoist.com/oauth/authorize"
    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["scope"] == "data:read"
    assert query["client_id"] == "todoist-client"
    assert query["redirect_uri"] == "http://www.marskal.example/imports/todoist/callback"

    conn =
      get(
        conn,
        ~p"/imports/todoist/callback?#{[code: "abc", state: query["state"]]}"
      )

    batch = last_batch(user)
    assert redirected_to(conn) == ~p"/imports/#{batch.id}"
    assert batch.source == "todoist"
    assert batch.channel == :oauth
    assert batch.external_account == "ada@marskal.example"
    assert_enqueued(worker: ParseJob, args: %{batch_id: batch.id})

    payload = Imports.load_payload(batch).payload
    assert payload =~ "Buy milk"
    refute payload =~ "token-1"
    refute payload =~ "do-not-store"

    drain_imports!()
    batch = Repo.reload!(batch)
    assert batch.status == :previewed
    assert batch.stats["tasks"] == 4
    assert batch.stats["tags"] == 5
    assert batch.stats["problems"] == 2

    conn = get(recycle(conn), ~p"/imports/#{batch.id}")
    html = html_response(conn, 200)
    assert html =~ "Labels become tags"
    assert html =~ "2 items could not be brought over in full"
    assert html =~ "Buy milk"
  end

  test "todoist callback rejects a mismatched state", %{conn: conn, user: user} do
    conn = get(conn, ~p"/imports/todoist")
    conn = get(conn, ~p"/imports/todoist/callback?#{[code: "abc", state: "nope"]}")

    assert redirected_to(conn) == ~p"/imports"
    assert batch_count(user) == 0

    conn = get(recycle(conn), ~p"/imports")
    assert html_response(conn, 200) =~ "could not be confirmed"
  end

  test "todoist callback reports a declined sign-in", %{conn: conn, user: user} do
    conn = get(conn, ~p"/imports/todoist")
    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    conn =
      get(
        conn,
        ~p"/imports/todoist/callback?#{[error: "access_denied", state: query["state"]]}"
      )

    assert redirected_to(conn) == ~p"/imports"
    assert batch_count(user) == 0
    conn = get(recycle(conn), ~p"/imports")
    assert html_response(conn, 200) =~ "Todoist access was declined"
  end

  test "upload parses and previews", %{conn: conn, user: user} do
    before = batch_count(user)

    conn =
      post(conn, ~p"/imports", %{
        "import_batch" => %{
          "payload" => upload(OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
        }
      })

    assert batch_count(user) == before + 1
    assert redirected_to(conn) =~ ~r"/imports/"

    batch = last_batch(user)
    assert batch.status == :pending
    assert_enqueued(worker: ParseJob, args: %{batch_id: batch.id})

    conn = get(recycle(conn), ~p"/imports/#{batch.id}")
    html = html_response(conn, 200)
    assert html =~ "Reading the backup"
    assert html =~ ~s(aria-label="New folder")
    refute html =~ ~s(http-equiv="refresh")

    drain_imports!()
    batch = Repo.reload!(batch)
    assert batch.status == :previewed
    assert batch.stats["folders"] == 2
    assert batch.stats["projects"] == 1

    conn = get(recycle(conn), ~p"/imports/#{batch.id}")
    html = html_response(conn, 200)
    assert html =~ "Launch website"
    assert html =~ "Import into Marskal"
    refute html =~ ~s(http-equiv="refresh")
  end

  test "upload ofocus-backup package members as a bundle", %{conn: conn, user: user} do
    {:ok, entries} = :zip.unzip(OmnifocusBackup.tutorial_backup(), [:memory])
    {files, paths} = unzipped_uploads(entries)
    before = batch_count(user)

    conn =
      post(conn, ~p"/imports", %{
        "import_batch" => %{"bundle_files" => files, "bundle_paths" => paths}
      })

    assert batch_count(user) == before + 1
    batch = last_batch(user)
    assert redirected_to(conn) == ~p"/imports/#{batch.id}"
    assert batch.status == :pending

    drain_imports!()
    batch = Repo.reload!(batch)
    assert batch.status == :previewed
    assert batch.stats["projects"] == 2
  end

  test "apply writes records", %{conn: conn, user: user} do
    {:ok, batch} =
      Imports.ingest_upload(user, %{
        "payload" => upload(OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
      })

    drain_imports!()
    batch = Repo.reload!(batch)
    assert batch.status == :previewed

    conn = post(conn, ~p"/imports/#{batch.id}/apply")
    assert redirected_to(conn) == ~p"/imports/#{batch.id}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Importing"
    batch = Repo.reload!(batch)
    assert batch.status == :applying
    assert_enqueued(worker: ApplyJob, args: %{batch_id: batch.id})
    refute Repo.get_by(Task, user_id: user.id, title: "Buy milk")

    conn = get(recycle(conn), ~p"/imports/#{batch.id}")
    assert html_response(conn, 200) =~ "Writing tags, folders, projects, and tasks"

    drain_imports!()
    assert Repo.reload!(batch).status == :applied
    assert Repo.get_by(Task, user_id: user.id, title: "Buy milk")

    conn = get(recycle(conn), ~p"/imports/#{batch.id}")
    assert html_response(conn, 200) =~ "Created tasks"
  end

  test "rejects too many imports in an hour", %{conn: conn, user: user} do
    limit = %Limits{}.imports_per_hour

    for _ <- 1..limit do
      %ImportBatch{}
      |> ImportBatch.changeset(%{
        user_id: user.id,
        source: "omnifocus",
        channel: :file,
        status: :failed,
        filename: "x.ofocus-backup",
        payload: "nope"
      })
      |> Repo.insert!()
    end

    before = batch_count(user)

    conn =
      post(conn, ~p"/imports", %{
        "import_batch" => %{
          "payload" => upload(OmnifocusBackup.compact_backup(), "OmniFocus.ofocus-backup")
        }
      })

    assert redirected_to(conn) == ~p"/imports/new"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many imports"
    assert batch_count(user) == before
  end

  test "cannot show another user's batch", %{conn: conn} do
    other = user_fixture()

    batch =
      %ImportBatch{}
      |> ImportBatch.changeset(%{
        user_id: other.id,
        source: "omnifocus",
        channel: :file,
        status: :failed,
        filename: "x.ofocus-backup",
        payload: "nope"
      })
      |> Repo.insert!()

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/imports/#{batch.id}")
    assert to == ~p"/imports"
  end

  test "taskpaper outline imports and the download updates the same records", %{
    conn: conn,
    user: user
  } do
    outline = """
    Inbox:
    \t- First
    \t- Second
    Work: @tags(Focus) @url(https://example.com/work)
    \tNotes for the project
    \t- Parent task
    \t\t- Child
    - Loose @dropped
    This line is left out
    """

    conn =
      post(conn, ~p"/imports", %{
        "import_batch" => %{
          "kind" => "taskpaper",
          "payload" => upload(outline, "outline.taskpaper")
        }
      })

    batch = last_batch(user)
    assert redirected_to(conn) == ~p"/imports/#{batch.id}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Reading the outline"
    assert batch.source == "taskpaper"

    drain_imports!()
    batch = Repo.reload!(batch)
    assert batch.status == :previewed
    assert batch.stats["tasks"] == 5
    assert batch.stats["projects"] == 1
    assert batch.stats["tags"] == 1
    assert batch.stats["inbox"] == 2
    assert batch.stats["skipped_rows"] == 1

    conn = get(recycle(conn), ~p"/imports/#{batch.id}")
    html = html_response(conn, 200)
    assert html =~ "A project named Inbox is the inbox"
    assert html =~ "1 line was left out."

    conn = post(recycle(conn), ~p"/imports/#{batch.id}/apply")
    assert redirected_to(conn) == ~p"/imports/#{batch.id}"
    drain_imports!()
    assert Repo.reload!(batch).status == :applied

    first = Repo.get_by!(Task, user_id: user.id, title: "First")
    second = Repo.get_by!(Task, user_id: user.id, title: "Second")
    assert first.inbox and second.inbox
    assert first.rank < second.rank

    project = Repo.get_by!(Marskal.Projects.Project, user_id: user.id, title: "Work")
    assert project.notes == "Notes for the project"
    assert project.url == "https://example.com/work"
    tag = Repo.get_by!(Marskal.Tags.Tag, user_id: user.id, name: "Focus")

    assert Repo.get_by!(Marskal.Tags.ProjectTag, project_id: project.id, tag_id: tag.id).discarded_at ==
             nil

    parent = Repo.get_by!(Task, user_id: user.id, title: "Parent task")
    child = Repo.get_by!(Task, user_id: user.id, title: "Child")
    assert child.parent_id == parent.id
    assert child.project_id == project.id
    assert parent.project_id == project.id

    loose = Repo.get_by!(Task, user_id: user.id, title: "Loose")
    assert loose.state == :dropped
    refute loose.inbox
    assert loose.project_id == nil

    conn = get(recycle(conn), ~p"/exports/taskpaper")
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
    assert get_resp_header(conn, "content-type") |> hd() =~ "charset=utf-8"
    disposition = get_resp_header(conn, "content-disposition") |> hd()
    assert disposition =~ "attachment"
    assert disposition =~ ".taskpaper"
    body = response(conn, 200)
    assert body =~ "Parent task"
    assert body =~ "@id(#{parent.id})"

    again =
      post(recycle(conn), ~p"/imports", %{
        "import_batch" => %{
          "kind" => "taskpaper",
          "payload" =>
            upload(String.replace(body, "Parent task", "Renamed task"), "again.taskpaper")
        }
      })

    reimport = last_batch(user)
    assert redirected_to(again) == ~p"/imports/#{reimport.id}"
    drain_imports!()
    post(recycle(again), ~p"/imports/#{reimport.id}/apply")
    drain_imports!()
    assert Repo.reload!(reimport).status == :applied
    assert Repo.get!(Task, parent.id).title == "Renamed task"

    assert Repo.aggregate(
             from(t in Task, where: t.user_id == ^user.id and is_nil(t.discarded_at)),
             :count
           ) == 5
  end

  test "a file that is not an outline fails and offers another file", %{conn: conn, user: user} do
    conn =
      post(conn, ~p"/imports", %{
        "import_batch" => %{
          "kind" => "taskpaper",
          "payload" => upload("just words\n", "notes.taskpaper")
        }
      })

    batch = last_batch(user)
    drain_imports!()
    batch = Repo.reload!(batch)
    assert batch.status == :failed
    assert batch.source == "taskpaper"
    assert batch.error_message =~ "not a TaskPaper outline"

    conn = get(recycle(conn), ~p"/imports/#{batch.id}")
    assert html_response(conn, 200) =~ "/imports/taskpaper"

    post(recycle(conn), ~p"/imports", %{
      "import_batch" => %{
        "kind" => "taskpaper",
        "payload" => upload(<<0xFF, 0xFE>>, "bad.taskpaper")
      }
    })

    batch = last_batch(user)
    drain_imports!()
    assert Repo.reload!(batch).error_message =~ "UTF-8"
  end

  test "taskpaper export requires sign in" do
    conn = build_conn() |> get(~p"/exports/taskpaper")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  defp drain_imports! do
    assert %{failure: 0, discard: 0} = Oban.drain_queue(queue: :imports)
  end

  defp batch_count(user) do
    Repo.aggregate(from(b in ImportBatch, where: b.user_id == ^user.id), :count)
  end

  defp last_batch(user) do
    ImportBatch
    |> where([b], b.user_id == ^user.id)
    |> order_by([b], desc: b.inserted_at, desc: b.id)
    |> limit(1)
    |> Repo.one!()
  end

  defp upload(bytes, filename) do
    path =
      Path.join(System.tmp_dir!(), "marskal-#{System.unique_integer([:positive])}-#{filename}")

    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: filename, content_type: "application/zip"}
  end

  defp unzipped_uploads(entries) do
    entries
    |> Enum.reject(fn {name, _} -> to_string(name) |> String.ends_with?("/") end)
    |> Enum.map(fn {name, data} ->
      path = to_string(name)
      file = upload(data, Path.basename(path))
      {file, path}
    end)
    |> Enum.unzip()
  end
end
