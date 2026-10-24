defmodule Marskal.GoToTest do
  use Marskal.DataCase, async: true

  import Marskal.AccountsFixtures

  alias Marskal.GoTo
  alias Marskal.GoTo.Target
  alias Marskal.ProjectFolders
  alias Marskal.ProjectNav
  alias Marskal.Projects
  alias Marskal.Tags

  setup do
    user = user_fixture()
    {:ok, work} = ProjectFolders.create_folder(user, %{"name" => "Work"}, command())

    {:ok, website} =
      Projects.create_project(
        user,
        %{"title" => "Website", "project_folder_id" => work.id},
        command()
      )

    {:ok, _taxes} = Projects.create_project(user, %{"title" => "Taxes"}, command())
    {:ok, home} = Tags.create_tag(user, %{"name" => "Home"}, command())

    {:ok, _garden} =
      Tags.create_tag(user, %{"name" => "Garden", "parent_id" => home.id}, command())

    %{user: user, work: work, website: website}
  end

  test "folders, projects, and tags have their paths", %{user: user} do
    targets = GoTo.targets(user, ProjectNav.build(user))

    assert {:folder, ["Work"]} in kinds(targets)
    assert {:project, ["Work", "Website"]} in kinds(targets)
    assert {:project, ["Taxes"]} in kinds(targets)
    assert {:tag, ["Home", "Garden"]} in kinds(targets)
  end

  test "a path matches across folders, and an exact name ranks first", %{user: user} do
    targets = GoTo.targets(user, ProjectNav.build(user))

    assert paths(GoTo.run(targets, "wo/web")) == [["Work", "Website"]]
    assert paths(GoTo.run(targets, "work")) |> hd() == ["Work"]
    assert paths(GoTo.run(targets, "gar")) == [["Home", "Garden"]]
    assert GoTo.run(targets, " ") == []
  end

  test "what the sidebar hides is offered after what it shows", %{
    user: user,
    website: website
  } do
    {:ok, _webinar} = Projects.create_project(user, %{"title" => "Webinar"}, command())
    {:ok, _} = Projects.update_project(user, website.id, %{"state" => "done"}, command())

    targets = GoTo.targets(user, ProjectNav.build(user))
    [first, second] = GoTo.run(targets, "web")

    assert {first.path, first.hidden} == {["Webinar"], false}
    assert {second.path, second.hidden, second.state} == {["Work", "Website"], true, :done}
  end

  test "the caller's views rank before records" do
    view = %Target{type: :view, id: :inbox, path: ["Inbox"]}
    project = %Target{type: :project, id: "p", path: ["Inbox zero"]}

    assert GoTo.run([project, view], "in") == [view, project]
  end

  test "another user's records are not targets", %{user: user} do
    other = user_fixture()
    assert GoTo.targets(other, ProjectNav.build(other)) == []
    assert GoTo.targets(user, ProjectNav.build(user)) != []
  end

  defp kinds(targets), do: Enum.map(targets, &{&1.type, &1.path})
  defp paths(targets), do: Enum.map(targets, & &1.path)
  defp command, do: Ecto.UUID.generate(version: 7)
end
