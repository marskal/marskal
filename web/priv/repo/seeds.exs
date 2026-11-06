# Sample data for local development. Idempotent. Never required in production.
#
#   mix run priv/repo/seeds.exs
#
# Sign in as:
#   mts@marskal.example / H3mm3l1gh3d  — superuser, folders, projects, tasks;
#                                        en-DK dates, agenda home, Vim-style keys
#   kvp@marskal.example / H3mm3l1gh3d  — second user, one open task
#
# Existing tasks are left in place. Folders and projects are added when
# the account has none yet.

password = "H3mm3l1gh3d"

defmodule Marskal.DevSeed do
  import Ecto.Query

  def user!(email, superuser, password) do
    case Marskal.Repo.get_by(Marskal.Accounts.User, email: email) do
      %Marskal.Accounts.User{} = user ->
        user

      nil ->
        %Marskal.Accounts.User{}
        |> Ecto.Changeset.change(%{
          email: email,
          hashed_password: Argon2.hash_pwd_salt(password),
          confirmed_at: DateTime.utc_now(:second),
          superuser: superuser
        })
        |> Marskal.Repo.insert!()
    end
  end

  # Set on every run, so a session that changed them gets them back.
  def preferences!(user, attrs) do
    {:ok, _} = Marskal.Accounts.update_preferences(user, attrs, Ecto.UUID.generate(version: 7))
  end

  def tasks!(user, rows) do
    already? =
      Marskal.Repo.exists?(
        from t in Marskal.Tasks.Task,
          where: t.user_id == ^user.id
      )

    unless already? do
      Enum.each(rows, fn row -> insert!(user, row) end)
    end
  end

  def structure!(user) do
    if Marskal.Repo.exists?(
         from f in Marskal.ProjectFolders.ProjectFolder,
           where: f.user_id == ^user.id
       ) do
      :ok
    else
      work = folder!(user, "Work")
      client_a = folder!(user, "Client A", work.id)
      folder!(user, "Internal", work.id)
      home = folder!(user, "Home")
      folder!(user, "Side projects")
      archive = folder!(user, "Old archive")
      Marskal.ProjectFolders.drop_folder(user, archive.id, Ecto.UUID.generate())

      website = project!(user, "Launch website", client_a.id, "Public marketing site.")

      review =
        project!(user, "Quarterly review", work.id, "Collect numbers, write the one-pager.")

      reno = project!(user, "Kitchen reno", home.id, "Cabinets and countertop only.")
      project!(user, "Plan vacation", nil, "Unfiled on purpose.")
      done = project!(user, "Finish onboarding", nil, "Welcome email shipped.")
      Marskal.Projects.complete_project(user, done.id, Ecto.UUID.generate())

      abandoned =
        project!(
          user,
          "Abandoned blog",
          archive.id,
          "Parked. The folder is dropped; the project remains."
        )

      Marskal.Projects.drop_project(user, abandoned.id, Ecto.UUID.generate())

      task!(user, "Draft homepage copy", website.id)
      task!(user, "Set up analytics", website.id)
      bought = task!(user, "Buy the domain", website.id)
      Marskal.Tasks.complete_task(user, bought.id, Ecto.UUID.generate())
      mascot = task!(user, "Commission a mascot", website.id)
      Marskal.Tasks.drop_task(user, mascot.id, Ecto.UUID.generate())
      task!(user, "Collect last quarter's metrics", review.id)
      task!(user, "Get three cabinet quotes", reno.id)
      vacation = Marskal.Projects.get_project(user, project_id_by_title(user, "Plan vacation"))
      task!(user, "Pick travel dates", vacation.id)
    end
  end

  defp folder!(user, name, parent_id \\ nil) do
    {:ok, folder} =
      Marskal.ProjectFolders.create_folder(
        user,
        %{"name" => name, "parent_id" => parent_id},
        Ecto.UUID.generate()
      )

    folder
  end

  defp project!(user, title, folder_id, notes) do
    {:ok, project} =
      Marskal.Projects.create_project(
        user,
        %{"title" => title, "notes" => notes, "project_folder_id" => folder_id},
        Ecto.UUID.generate()
      )

    project
  end

  defp task!(user, title, project_id) do
    {:ok, task} =
      Marskal.Tasks.create_task(
        user,
        %{"title" => title, "project_id" => project_id},
        Ecto.UUID.generate()
      )

    task
  end

  defp project_id_by_title(user, title) do
    Marskal.Repo.get_by!(Marskal.Projects.Project, user_id: user.id, title: title).id
  end

  defp insert!(user, {title, notes, days_ago, placement}) do
    command = Ecto.UUID.generate()
    {:ok, task} = Marskal.Tasks.create_task(user, %{title: title, notes: notes}, command)

    task =
      case placement do
        :inbox ->
          task

        :open ->
          {:ok, task} = Marskal.Tasks.move_task(user, task.id, :none, Ecto.UUID.generate())
          task

        :done ->
          {:ok, task} = Marskal.Tasks.move_task(user, task.id, :none, Ecto.UUID.generate())
          {:ok, task} = Marskal.Tasks.complete_task(user, task.id, Ecto.UUID.generate())
          task

        :dropped ->
          {:ok, task} = Marskal.Tasks.drop_task(user, task.id, Ecto.UUID.generate())
          task
      end

    at = DateTime.utc_now(:second) |> DateTime.add(-days_ago * 86_400, :second)

    task
    |> Ecto.Changeset.change(%{inserted_at: at, updated_at: at})
    |> Marskal.Repo.update!()
  end
end

dev = Marskal.DevSeed.user!("mts@marskal.example", true, password)
other = Marskal.DevSeed.user!("kvp@marskal.example", false, password)

Marskal.DevSeed.preferences!(dev, %{locale: "en-DK", home_view: :agenda, keymap: :vim})
Marskal.DevSeed.structure!(dev)

Marskal.DevSeed.tasks!(dev, [
  {"Buy milk", "From the corner shop.", 1, :inbox},
  {"Call the dentist", nil, 2, :inbox},
  {"Diagnose the weird car noise", "Only when turning left.", 3, :inbox},
  {"Review folder breadcrumbs against ADR 0009", nil, 5, :open},
  {"Sketch a weekly review checklist", nil, 7, :open},
  {"Finish Rails auth", nil, 45, :done},
  {"Evaluate a third note-taking app", nil, 50, :dropped}
])

Marskal.DevSeed.tasks!(other, [
  {"Secret task", nil, 16, :open}
])

IO.puts("Sample accounts (password: #{password}):")
IO.puts("  #{dev.email}  — superuser")
IO.puts("  #{other.email} — second user")
