defmodule MarskalWeb.ImportLiveTest do
  use MarskalWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marskal.AccountsFixtures

  alias Marskal.ImportBatch
  alias Marskal.Repo

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "an applied re-import shows updates and the edits it kept", %{conn: conn, user: user} do
    batch =
      Repo.insert!(%ImportBatch{
        user_id: user.id,
        source: "todoist",
        channel: :oauth,
        status: :applied,
        filename: "Todoist",
        stats: %{
          "created" => %{"tasks" => 1},
          "updated" => %{"tasks" => 2, "projects" => 1},
          "skipped" => %{"tasks" => 4},
          "kept" => 1,
          "kept_samples" => [%{"kind" => "tasks", "title" => "Write copy", "fields" => ["notes"]}]
        }
      })

    {:ok, view, _html} = live(conn, ~p"/imports/#{batch.id}")

    assert has_element?(view, "dt", "Updated")
    assert has_element?(view, "dd", "3")
    assert has_element?(view, "#import-kept li", "Write copy")
    assert has_element?(view, "#import-kept li", "(notes)")
  end
end
