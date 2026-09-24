class ProjectsController < ApplicationController
  before_action :set_project, only: %i[ show update complete drop reopen ]

  def index
    active_folders = current_user_folders.active.ordered.to_a
    @folders_by_parent = active_folders.group_by(&:parent_id)
    @root_folders = @folders_by_parent[nil] || []
    @unfiled_projects = current_user_projects.open_stream.unfiled.recent_first
    @project = Project.new
    @folder = ProjectFolder.new
    @folder_options = folder_select_options(active_folders)
  end

  def show
    if turbo_frame_request?
      load_inspector_extras
      render :inspector, layout: false
      return
    end

    @tasks = @project.open_tasks
    @task = Task.new(project: @project)
    @folder_options = folder_select_options
  end

  def create
    @project = current_user_projects.new(project_params)
    @project.state = :to_do

    if @project.save
      redirect_to @project, notice: "Project added."
    else
      active_folders = current_user_folders.active.ordered.to_a
      @folders_by_parent = active_folders.group_by(&:parent_id)
      @root_folders = @folders_by_parent[nil] || []
      @unfiled_projects = current_user_projects.open_stream.unfiled.recent_first
      @folder = ProjectFolder.new
      @folder_options = folder_select_options(active_folders)
      flash.now[:alert] = @project.errors.full_messages.to_sentence.presence || "Could not add project."
      render :index, status: :unprocessable_entity
    end
  end

  def update
    updated = @project.update(project_params)
    @project.reload if updated
    load_inspector_extras

    if updated
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @project, notice: "Updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
        format.html do
          @tasks = @project.open_tasks
          @task = Task.new(project: @project)
          flash.now[:alert] = @project.errors.full_messages.to_sentence.presence || "Could not update project."
          render :show, status: :unprocessable_entity
        end
      end
    end
  end

  def complete
    @project.complete!
    redirect_to projects_path, notice: "Project done."
  end

  def drop
    @project.drop!
    redirect_to projects_path, notice: "Project dropped."
  end

  def reopen
    @project.reopen!
    redirect_to @project, notice: "Project reopened."
  end

  private
    def current_user_projects
      Current.user.projects
    end

    def current_user_folders
      Current.user.project_folders
    end

    def set_project
      @project = current_user_projects.find(params[:id])
    end

    def project_params
      attrs = params.require(:project).permit(:title, :notes, :project_folder_id, :state)
      attrs[:project_folder_id] = nil if attrs.key?(:project_folder_id) && attrs[:project_folder_id].blank?
      attrs
    end

    def folder_select_options(folders = nil)
      folders ||= current_user_folders.active.ordered
      folders.map { |f| [ f.breadcrumb_label, f.id ] }
    end

    def load_inspector_extras
      @folder_options = inspector_folder_options(@project)
      @list_context = params[:list_context].presence_in(%w[projects_index folder])
      @list_folder_id = params[:list_folder_id].presence
    end

    def inspector_folder_options(project)
      folders = current_user_folders.active.ordered.to_a
      current = project.project_folder
      if current && current.user_id == Current.user.id && folders.none? { |folder| folder.id == current.id }
        folders.unshift(current)
      end
      folders.map { |folder| [ folder.breadcrumb_label, folder.id ] }
    end

    def inspector_card_visible?
      case @list_context
      when "projects_index"
        @project.to_do? && @project.project_folder_id.nil?
      when "folder"
        @project.to_do? && @project.project_folder_id.to_s == @list_folder_id.to_s
      else
        true
      end
    end
    helper_method :inspector_card_visible?
end
