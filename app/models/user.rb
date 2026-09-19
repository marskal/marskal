class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :project_folders, dependent: :destroy
  has_many :import_batches, dependent: :destroy
  has_many :import_items, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Development helper: wipe captured work, keep the account.
  def reset_captured_work!
    transaction do
      import_items.delete_all
      import_batches.find_each(&:destroy!)
      tasks.delete_all
      projects.delete_all
      project_folders.update_all(parent_id: nil)
      project_folders.delete_all
    end
  end
end
