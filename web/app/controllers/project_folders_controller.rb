class ProjectFoldersController < ApplicationController
  before_action :set_folder, only: %i[ show update drop activate ]

  def show
    if turbo_frame_request?
      load_inspector_extras
      render :inspector, layout: false
      return
    end

    @child_folders = @folder.children.active.ordered
    @projects = @folder.open_projects
    @project = Project.new(project_folder: @folder)
    @child_folder = ProjectFolder.new(parent: @folder)
  end

  def create
    @folder = current_user_folders.new(folder_params)
    @folder.state = :active

    if @folder.save
      redirect_to project_folder_path(@folder), notice: "Folder added."
    else
      redirect_back_or_to projects_path, alert: @folder.errors.full_messages.to_sentence.presence || "Could not add folder."
    end
  end

  def update
    updated = @folder.update(folder_params)
    @folder.reload if updated
    load_inspector_extras

    if updated
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to project_folder_path(@folder), notice: "Folder updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
        format.html { redirect_to project_folder_path(@folder), alert: @folder.errors.full_messages.to_sentence.presence || "Could not update folder." }
      end
    end
  end

  def drop
    @folder.drop!
    redirect_to projects_path, notice: "Folder dropped."
  end

  def activate
    @folder.activate!
    redirect_to project_folder_path(@folder), notice: "Folder active again."
  end

  private
    def current_user_folders
      Current.user.project_folders
    end

    def set_folder
      @folder = current_user_folders.find(params[:id])
    end

    def folder_params
      attrs = params.require(:project_folder).permit(:name, :parent_id, :state)
      attrs[:parent_id] = nil if attrs.key?(:parent_id) && attrs[:parent_id].blank?
      attrs
    end

    def load_inspector_extras
      @parent_options = inspector_parent_options(@folder)
      @list_context = params[:list_context].presence_in(%w[projects_index folder])
    end

    def inspector_parent_options(folder)
      excluded = folder.subtree_ids
      folders = current_user_folders.active.ordered.reject { |candidate| excluded.include?(candidate.id) }
      current = folder.parent
      if current && current.user_id == Current.user.id && folders.none? { |candidate| candidate.id == current.id }
        folders.unshift(current)
      end
      folders.map { |candidate| [ candidate.breadcrumb_label, candidate.id ] }
    end

    def inspector_row_visible?
      case @list_context
      when "projects_index", "folder"
        @folder.active?
      else
        true
      end
    end
    helper_method :inspector_row_visible?
end
