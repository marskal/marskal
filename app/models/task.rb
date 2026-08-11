class Task < ApplicationRecord
  include LifecycleState

  belongs_to :user
  belongs_to :project, optional: true

  validates :title, presence: true
  validate :project_must_belong_to_same_user

  scope :inbox, -> { where(inbox: true) }
  scope :not_inbox, -> { where(inbox: false) }
  scope :open_stream, -> { to_do.not_inbox }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def move_to_open!
    update!(inbox: false)
  end

  private
    def project_must_belong_to_same_user
      return if project_id.blank?
      return if project&.user_id == user_id

      errors.add(:project, "must belong to the same user")
    end
end
