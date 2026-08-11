class Task < ApplicationRecord
  belongs_to :user

  STATES = %w[to_do done dropped].freeze

  enum :state, {
    to_do: "to_do",
    done: "done",
    dropped: "dropped"
  }, validate: true

  validates :title, presence: true

  scope :inbox, -> { where(inbox: true) }
  scope :not_inbox, -> { where(inbox: false) }
  scope :open_stream, -> { to_do.not_inbox }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def move_to_open!
    update!(inbox: false)
  end

  def complete!
    update!(state: :done)
  end

  def drop!
    update!(state: :dropped)
  end

  def reopen!
    update!(state: :to_do)
  end
end
