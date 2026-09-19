class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :project_nav_tree, :show_task_inspector?, :inspector_frame_src

  private
    def project_nav_tree
      @project_nav_tree ||= ProjectNavTree.new(Current.user)
    end

    def show_task_inspector?
      (controller_name == "tasks" && action_name.in?(%w[index inbox])) ||
        (controller_name == "projects" && action_name == "show")
    end

    def inspector_frame_src
      id = params[:task]
      return unless id.is_a?(String) && id.present?

      task_path(id, inspector_list_params)
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
