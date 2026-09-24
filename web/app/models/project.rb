class Project < ApplicationRecord
  include LifecycleState

  belongs_to :user
  belongs_to :project_folder, optional: true
  has_many :tasks, dependent: :nullify

  validates :title, presence: true
  validate :folder_must_belong_to_same_user

  scope :open_stream, -> { to_do }
  scope :unfiled, -> { where(project_folder_id: nil) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def open_tasks
    tasks.open_stream.recent_first
  end

  private
    def folder_must_belong_to_same_user
      return if project_folder_id.blank?
      return if project_folder&.user_id == user_id

      errors.add(:project_folder, "must belong to the same user")
    end
end
