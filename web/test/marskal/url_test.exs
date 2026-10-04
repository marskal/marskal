defmodule Marskal.UrlTest do
  use Marskal.DataCase, async: true

  alias Marskal.AccountsFixtures
  alias Marskal.Projects
  alias Marskal.Repo
  alias Marskal.Tasks
  alias Marskal.Url

  setup do
    %{user: AccountsFixtures.user_fixture()}
  end

  test "a task and a project keep any absolute URL", %{user: user} do
    for url <- [
          "https://www.vivit.dk/kalender/",
          "file:///Users/me/Documents/plan.md",
          "mailto:someone@example.com",
          "obsidian://open?vault=Notes&file=Plan"
        ] do
      assert {:ok, task} = Tasks.create_task(user, %{"title" => "T", "url" => url}, command())
      assert task.url == url

      assert {:ok, project} =
               Projects.create_project(user, %{"title" => "P", "url" => url}, command())

      assert project.url == url
    end
  end

  test "surrounding whitespace is trimmed, and blank clears", %{user: user} do
    {:ok, task} =
      Tasks.create_task(user, %{"title" => "T", "url" => "  https://a.example  "}, command())

    assert task.url == "https://a.example"

    {:ok, task} = Tasks.update_task(user, task.id, %{"url" => "   "}, command())
    assert task.url == nil
  end

  test "refuses a relative URL, whitespace, and scripts", %{user: user} do
    for url <- [
          "www.example.com",
          "/tmp/file",
          "https://a.example/with space",
          "javascript:alert(1)",
          "JavaScript:alert(1)",
          "data:text/html,<script>alert(1)</script>",
          "vbscript:msgbox",
          "https://a.example/" <> String.duplicate("a", Url.max())
        ] do
      assert {:error, changeset} =
               Tasks.create_task(user, %{"title" => "T", "url" => url}, command())

      assert errors_on(changeset)[:url], url

      assert {:error, changeset} =
               Projects.create_project(user, %{"title" => "P", "url" => url}, command())

      assert errors_on(changeset)[:url], url
    end
  end

  test "the database checks the shape too", %{user: user} do
    {:ok, task} = Tasks.create_task(user, %{"title" => "T"}, command())

    assert_raise Postgrex.Error, ~r/tasks_url_absolute/, fn ->
      Repo.query!("UPDATE tasks SET url = 'not a url' WHERE id = $1", [Ecto.UUID.dump!(task.id)])
    end
  end

  test "safe? leaves out the refused schemes" do
    assert Url.safe?("https://a.example")
    assert Url.safe?("file:///tmp/x")
    refute Url.safe?(" javascript:alert(1)")
    refute Url.safe?("Javascript:alert(1)")
    refute Url.safe?("data:text/html,x")
    refute Url.safe?(nil)
  end

  defp command, do: Ecto.UUID.generate()
end
