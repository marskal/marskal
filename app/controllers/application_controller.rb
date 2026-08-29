class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :project_nav_tree

  private
    def project_nav_tree
      @project_nav_tree ||= ProjectNavTree.new(Current.user)
    end
end
