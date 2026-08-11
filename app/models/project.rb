class Project < ApplicationRecord
  include LifecycleState

  belongs_to :user
  has_many :tasks, dependent: :nullify

  validates :title, presence: true

  scope :open_stream, -> { to_do }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def open_tasks
    tasks.open_stream.recent_first
  end
end
