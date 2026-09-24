module LifecycleState
  extend ActiveSupport::Concern

  included do
    enum :state, {
      to_do: "to_do",
      done: "done",
      dropped: "dropped"
    }, validate: true
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
