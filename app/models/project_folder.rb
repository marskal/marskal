class ProjectFolder < ApplicationRecord
  belongs_to :user
  belongs_to :parent, class_name: "ProjectFolder", optional: true, inverse_of: :children
  has_many :children,
           class_name: "ProjectFolder",
           foreign_key: :parent_id,
           inverse_of: :parent,
           dependent: :restrict_with_error
  has_many :projects, dependent: :nullify

  enum :state, {
    active: "active",
    dropped: "dropped"
  }, validate: true

  validates :name, presence: true
  validate :parent_must_belong_to_same_user
  validate :parent_avoids_cycle

  before_validation :assign_parent_path
  after_update :cascade_parent_path_to_descendants, if: :saved_change_to_name_or_parent?

  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:name, :id) }

  def breadcrumb_segments
    parent_path + [ name ]
  end

  def breadcrumb_label
    breadcrumb_segments.join(" / ")
  end

  def drop!
    update!(state: :dropped)
  end

  def activate!
    update!(state: :active)
  end

  def open_projects
    projects.open_stream.recent_first
  end

  def subtree_ids
    [ id ] + children.flat_map(&:subtree_ids)
  end

  def refresh_descendant_paths!
    children.find_each do |child|
      child.update_columns(
        parent_path: parent_path + [ name ],
        updated_at: Time.current
      )
      child.refresh_descendant_paths!
    end
  end

  private
    def assign_parent_path
      if parent
        self.parent_path = parent.parent_path + [ parent.name ]
      else
        self.parent_path = []
      end
    end

    def parent_must_belong_to_same_user
      return if parent_id.blank?
      return if parent&.user_id == user_id

      errors.add(:parent, "must belong to the same user")
    end

    def parent_avoids_cycle
      return if parent_id.blank?
      return if id.blank?

      walker = parent
      while walker
        if walker.id == id
          errors.add(:parent, "would create a cycle")
          break
        end
        walker = walker.parent
      end
    end

    def saved_change_to_name_or_parent?
      saved_change_to_name? || saved_change_to_parent_id?
    end

    def cascade_parent_path_to_descendants
      refresh_descendant_paths!
    end
end
