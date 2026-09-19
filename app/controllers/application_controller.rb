class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :project_nav_tree, :show_inspector?, :inspector_frame_src

  private
    def project_nav_tree
      @project_nav_tree ||= ProjectNavTree.new(Current.user)
    end

    def show_inspector?
      (controller_name == "tasks" && action_name.in?(%w[index inbox])) ||
        (controller_name == "projects" && action_name.in?(%w[index show])) ||
        (controller_name == "project_folders" && action_name == "show")
    end

    def inspector_frame_src
      task_id = params[:task]
      return task_path(task_id, inspector_list_params) if task_id.is_a?(String) && task_id.present?

      project_id = params[:project]
      return project_path(project_id) if project_id.is_a?(String) && project_id.present?

      folder_id = params[:folder]
      return project_folder_path(folder_id) if folder_id.is_a?(String) && folder_id.present?

      return project_path(@project) if controller_name == "projects" && action_name == "show" && @project
      return project_folder_path(@folder) if controller_name == "project_folders" && action_name == "show" && @folder

      nil
    end

    def inspector_list_params
      extra = { list_context: inspector_list_context }
      extra[:list_project_id] = inspector_list_project_id if inspector_list_project_id.present?
      extra
    end

    def inspector_list_context
      if controller_name == "tasks" && action_name == "inbox"
        "inbox"
      elsif controller_name == "projects" && action_name == "show"
        "project"
      else
        "open"
      end
    end

    def inspector_list_project_id
      @project&.id if controller_name == "projects"
    end
end
