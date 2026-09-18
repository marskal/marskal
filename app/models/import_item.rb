# frozen_string_literal: true

class ImportItem < ApplicationRecord
  belongs_to :import_batch
  belongs_to :user
  belongs_to :project_folder, optional: true
  belongs_to :project, optional: true
  belongs_to :task, optional: true

  enum :kind, {
    folder: "folder",
    project: "project",
    task: "task"
  }, validate: true

  validates :source, :source_id, presence: true
end
