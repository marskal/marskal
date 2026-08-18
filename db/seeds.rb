# Sample data for local development (and CI `db:seed:replant`).
# Never runs in production.
#
#   bin/rails db:seed     # fill an empty local DB (idempotent)
#   bin/rails db:reset    # wipe + migrate + seed
#
# Sign in as:
#   mts@marskal.example   / H3mm3l1gh3d   — full sample graph
#   kvp@marskal.example / H3mm3l1gh3d   — isolated second user

return unless Rails.env.local?

module SampleData
  PASSWORD = "H3mm3l1gh3d"

  module_function

  def load
    dev = ensure_user!("mts@marskal.example")
    other = ensure_user!("kvp@marskal.example")

    seed_dev!(dev)
    seed_other!(other)

    puts "Sample accounts (password: #{PASSWORD}):"
    puts "  #{dev.email_address}   — inbox, open stream, folders, projects"
    puts "  #{other.email_address} — second user (isolation)"
  end

  def ensure_user!(email)
    user = User.find_or_initialize_by(email_address: email)
    user.password = PASSWORD
    user.save!
    user
  end

  def seed_dev!(user)
    return if account_populated?(user)

    work = folder!(user, "Work", days_ago: 40)
    client_a = folder!(user, "Client A", parent: work, days_ago: 38)
    folder!(user, "Internal", parent: work, days_ago: 37)
    home = folder!(user, "Home", days_ago: 36)
    folder!(user, "Side projects", days_ago: 20)
    archive = folder!(user, "Old archive", state: :dropped, days_ago: 200)

    website = project!(
      user,
      "Launch website",
      folder: client_a,
      notes: "Public marketing site. Done when the homepage is live and analytics fire.",
      days_ago: 30
    )
    review = project!(
      user,
      "Quarterly review",
      folder: work,
      notes: "Collect numbers, write the one-pager, send it before Friday.",
      days_ago: 14
    )
    reno = project!(
      user,
      "Kitchen reno",
      folder: home,
      notes: "Cabinets and countertop only — not a full gut.",
      days_ago: 21
    )
    vacation = project!(
      user,
      "Plan vacation",
      notes: "Unfiled on purpose — still deciding if this is a real project.",
      days_ago: 10
    )
    project!(
      user,
      "Finish onboarding",
      notes: "Welcome email and first-week checklist shipped.",
      state: :done,
      days_ago: 60
    )
    project!(
      user,
      "Abandoned blog",
      folder: archive,
      notes: "Parked. Folder is dropped; project is still here (ADR 0009).",
      state: :dropped,
      days_ago: 180
    )

    task!(user, "Draft homepage copy", project: website, days_ago: 12)
    task!(user, "Set up analytics", project: website, days_ago: 8)
    task!(user, "Buy the domain", project: website, state: :done, days_ago: 25)
    task!(user, "Commission a mascot", project: website, state: :dropped, days_ago: 18)

    task!(user, "Collect last quarter's metrics", project: review, days_ago: 6)
    task!(user, "Get three cabinet quotes", project: reno, days_ago: 15)
    task!(user, "Pick travel dates", project: vacation, days_ago: 4)

    task!(user, "Buy milk", inbox: true, notes: "From the corner shop.", days_ago: 1)
    task!(user, "Call the dentist", inbox: true, days_ago: 2)
    task!(user, "Diagnose the weird car noise", inbox: true, notes: "Only when turning left.", days_ago: 3)

    task!(user, "Review folder breadcrumbs against ADR 0009", days_ago: 5)
    task!(user, "Sketch a weekly review checklist", days_ago: 7)
    task!(user, "Finish Rails auth", state: :done, days_ago: 45)
    task!(user, "Evaluate a third note-taking app", state: :dropped, days_ago: 50)
  end

  def seed_other!(user)
    return if account_populated?(user)

    their_work = folder!(user, "Their Work", days_ago: 20)
    secret = project!(user, "Secret project", folder: their_work, days_ago: 18)
    task!(user, "Secret task", project: secret, days_ago: 16)
  end

  def account_populated?(user)
    user.project_folders.exists? || user.projects.exists? || user.tasks.exists?
  end

  def folder!(user, name, parent: nil, state: :active, days_ago:)
    user.project_folders.create!(
      name: name,
      parent: parent,
      state: state,
      **stamped(days_ago)
    )
  end

  def project!(user, title, folder: nil, notes: nil, state: :to_do, days_ago:)
    user.projects.create!(
      title: title,
      notes: notes,
      state: state,
      project_folder: folder,
      **stamped(days_ago)
    )
  end

  def task!(user, title, notes: nil, state: :to_do, inbox: false, project: nil, days_ago:)
    user.tasks.create!(
      title: title,
      notes: notes,
      state: state,
      inbox: inbox,
      project: project,
      **stamped(days_ago)
    )
  end

  def stamped(days_ago)
    at = days_ago.days.ago
    { created_at: at, updated_at: at }
  end
end

SampleData.load
