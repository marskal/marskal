# Sidebar tree of active folders and open projects (ADR 0009).
# Dropped folders, their descendants, and Done/Dropped projects stay out of default chrome.
class ProjectNavTree
  def initialize(user)
    @user = user
  end

  def empty?
    root_folders.empty? && unfiled_projects.empty?
  end

  def root_folders
    folders_by_parent[nil] || []
  end

  def child_folders(folder)
    folders_by_parent[folder.id] || []
  end

  def projects_in(folder)
    projects_by_folder[folder.id] || []
  end

  def unfiled_projects
    projects_by_folder[nil] || []
  end

  def expandable?(folder)
    child_folders(folder).any? || projects_in(folder).any?
  end

  private
    def folders_by_parent
      @folders_by_parent ||= folders.group_by(&:parent_id)
    end

    def projects_by_folder
      @projects_by_folder ||= projects.group_by(&:project_folder_id)
    end

    def folders
      return [] unless @user

      @folders ||= @user.project_folders.active.ordered.to_a
    end

    # All open projects. The view only walks reachable active folders, so items
    # filed under a dropped ancestor never appear (and are not hoisted).
    def projects
      return [] unless @user

      @projects ||= @user.projects.open_stream.order(:title, :id).to_a
    end
end
