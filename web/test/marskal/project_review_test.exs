defmodule Marskal.ProjectReviewTest do
  use Marskal.DataCase, async: true

  alias Marskal.Accounts
  alias Marskal.AccountsFixtures
  alias Marskal.Changes.Change
  alias Marskal.Dates
  alias Marskal.Projects
  alias Marskal.Projects.Project
  alias Marskal.Sync
  alias Marskal.Sync.Push

  @zone "Europe/Copenhagen"

  setup do
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  describe "a new project" do
    test "takes the default interval and is due that long after today", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())

      assert project.review_interval == Duration.new!(day: 7)
      assert project.next_review_on == Date.shift(Dates.today(@zone), day: 7)
      assert project.last_reviewed_at == nil
      assert Accounts.preferences(user).default_review_interval == Duration.new!(day: 7)
    end

    test "copies the preference when it is made, Never included", %{user: user} do
      {:ok, _} =
        Accounts.update_preferences(user, %{default_review_interval: "P1M"}, command())

      {:ok, monthly} = Projects.create_project(user, %{title: "Taxes"}, command())
      assert monthly.review_interval == Duration.new!(month: 1)
      assert monthly.next_review_on == Date.shift(Dates.today(@zone), month: 1)

      {:ok, _} = Accounts.update_preferences(user, %{default_review_interval: nil}, command())
      {:ok, never} = Projects.create_project(user, %{title: "Recipes"}, command())
      assert {never.review_interval, never.next_review_on} == {nil, nil}

      assert Repo.reload!(monthly).review_interval == Duration.new!(month: 1)
    end

    test "may name its own interval, in ISO 8601 of either case", %{user: user} do
      {:ok, project} =
        Projects.create_project(user, %{title: "Bike", review_interval: "p2w"}, command())

      assert project.review_interval == Duration.new!(day: 14)
      assert project.next_review_on == Date.shift(Dates.today(@zone), day: 14)

      {:ok, never} =
        Projects.create_project(user, %{title: "Notes", review_interval: nil}, command())

      assert never.next_review_on == nil
    end
  end

  describe "mark reviewed" do
    test "sets when, and the next day from today on the user's clock", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())
      at = ~U[2027-03-10 23:30:00Z]

      {:ok, reviewed} = Projects.mark_reviewed(user, project.id, command(), at: at)

      assert reviewed.last_reviewed_at == at
      # 00:30 on 11 March in Copenhagen.
      assert reviewed.next_review_on == ~D[2027-03-18]

      assert %Change{patch: %{"last_reviewed_at" => "2027-03-10T23:30:00Z"}} =
               Repo.one(from c in Change, order_by: [desc: c.id], limit: 1)
    end

    test "adds months, then days, and clamps to a short month's end", %{user: user} do
      {:ok, project} =
        Projects.create_project(user, %{title: "Bills", review_interval: "P1M1D"}, command())

      {:ok, reviewed} =
        Projects.mark_reviewed(user, project.id, command(), at: ~U[2027-01-31 12:00:00Z])

      assert reviewed.next_review_on == ~D[2027-03-01]

      {:ok, _} = Projects.update_project(user, project.id, %{review_interval: "P1M"}, command())

      {:ok, reviewed} =
        Projects.mark_reviewed(user, project.id, command(), at: ~U[2027-01-31 12:00:00Z])

      assert reviewed.next_review_on == ~D[2027-02-28]
    end

    test "refuses a project set to Never, and another user's", %{user: user, other: other} do
      {:ok, never} =
        Projects.create_project(user, %{title: "Notes", review_interval: nil}, command())

      assert Projects.mark_reviewed(user, never.id, command()) == {:error, :not_reviewed}
      assert Projects.mark_reviewed(other, never.id, command()) == {:error, :not_found}
    end
  end

  describe "changing the interval" do
    test "counts from the last review", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())

      {:ok, _} =
        Projects.mark_reviewed(user, project.id, command(), at: ~U[2027-01-04 09:00:00Z])

      {:ok, changed} =
        Projects.update_project(user, project.id, %{review_interval: "P1M"}, command())

      assert changed.next_review_on == ~D[2027-02-04]
    end

    test "counts from the creation day when never reviewed, which may be past", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())

      Repo.update_all(where(Project, id: ^project.id),
        set: [inserted_at: ~U[2027-01-04 23:30:00Z]]
      )

      {:ok, changed} =
        Projects.update_project(user, project.id, %{"review_interval" => "P2D"}, command())

      assert changed.next_review_on == ~D[2027-01-07]
    end

    test "to Never clears the next day, and back sets it again", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())

      {:ok, never} =
        Projects.update_project(user, project.id, %{review_interval: nil}, command())

      assert {never.review_interval, never.next_review_on} == {nil, nil}

      {:ok, weekly} =
        Projects.update_project(user, project.id, %{review_interval: "P1W"}, command())

      assert weekly.next_review_on ==
               Date.shift(elem(Dates.to_local(weekly.inserted_at, @zone), 0), day: 7)
    end

    test "the next day can be set on its own, but not under Never", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())

      {:ok, moved} =
        Projects.update_project(user, project.id, %{next_review_on: ~D[2027-05-01]}, command())

      assert moved.next_review_on == ~D[2027-05-01]
      assert moved.review_interval == Duration.new!(day: 7)

      {:ok, _} = Projects.update_project(user, project.id, %{review_interval: nil}, command())

      assert {:error, changeset} =
               Projects.update_project(
                 user,
                 project.id,
                 %{next_review_on: ~D[2027-05-01]},
                 command()
               )

      assert %{next_review_on: [_]} = errors_on(changeset)
    end

    test "refuses a time part, a negative part, and zero", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())

      for interval <- ["PT12H", "P1DT1H", "P-1D", "P0D", "every week"] do
        assert {:error, changeset} =
                 Projects.update_project(
                   user,
                   project.id,
                   %{review_interval: interval},
                   command()
                 )

        assert %{review_interval: [_]} = errors_on(changeset), interval
      end

      assert {:error, _} =
               Accounts.update_preferences(user, %{default_review_interval: "PT1H"}, command())
    end

    test "the database refuses a time part too", %{user: user} do
      {:ok, project} = Projects.create_project(user, %{title: "Garden"}, command())

      assert_raise Postgrex.Error, ~r/projects_review_interval/, fn ->
        Repo.query!("UPDATE projects SET review_interval = '1 day 2 hours' WHERE id = $1", [
          Ecto.UUID.dump!(project.id)
        ])
      end
    end
  end

  describe "sync" do
    test "pulls the interval as ISO 8601, weeks as days", %{user: user} do
      {:ok, project} =
        Projects.create_project(user, %{title: "Garden", review_interval: "P2W"}, command())

      {:ok, _} =
        Projects.mark_reviewed(user, project.id, command(), at: ~U[2027-01-04 09:00:00Z])

      assert [
               %{
                 "review_interval" => "P14D",
                 "next_review_on" => ~D[2027-01-18],
                 "last_reviewed_at" => "2027-01-04T09:00:00Z"
               }
             ] = Sync.pull(user, nil).rows["project"]

      assert [%{"default_review_interval" => "P7D"}] =
               Sync.pull(user, nil).rows["user_preferences"]

      assert %Change{patch: %{"review_interval" => "P14D"}} =
               Repo.one(from c in Change, order_by: [asc: c.id], limit: 1)
    end

    test "a client writes all three fields and the preference", %{user: user} do
      id = Ecto.UUID.generate(version: 7)

      assert [%{status: "applied"}] =
               Push.push(user, [
                 push("project", id, "insert", %{
                   "title" => "Garden",
                   "review_interval" => "P1Y",
                   "next_review_on" => "2027-06-01"
                 })
               ])

      project = Projects.get_project(user, id)
      assert project.review_interval == Duration.new!(year: 1)
      assert project.next_review_on == ~D[2027-06-01]

      assert [%{status: "applied"}] =
               Push.push(user, [
                 push("project", id, "patch", %{
                   "last_reviewed_at" => "2027-06-01T08:00:00Z",
                   "next_review_on" => "2028-06-01"
                 })
               ])

      assert [%{status: "rejected"}] =
               Push.push(user, [push("project", id, "patch", %{"review_interval" => "PT1H"})])

      assert [%{status: "applied"}] =
               Push.push(user, [
                 push("user_preferences", user.id, "patch", %{"default_review_interval" => "P3M"})
               ])

      assert Accounts.preferences(user).default_review_interval == Duration.new!(month: 3)
    end
  end

  defp command, do: Ecto.UUID.generate(version: 7)

  defp push(entity, id, op, fields),
    do: %{
      "id" => Ecto.UUID.generate(version: 7),
      "entity" => entity,
      "entity_id" => id,
      "op" => op,
      "fields" => fields
    }
end
