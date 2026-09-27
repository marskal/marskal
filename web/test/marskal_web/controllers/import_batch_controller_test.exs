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
  alias Marskal.Repo
  alias Marskal.Tasks.Task

  use Oban.Testing, repo: Marskal.Repo

  setup :register_and_log_in_user

  test "index requires sign in" do
    conn = build_conn() |> get(~p"/imports")
    assert redirected_to(conn) == ~p"/users/log-in"
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
    assert html =~ "Add folder"
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
