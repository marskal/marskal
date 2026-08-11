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
    if @project.update(project_params)
      redirect_to @project, notice: "Updated."
    else
      @tasks = @project.open_tasks
      @task = Task.new(project: @project)
      @folder_options = folder_select_options
      flash.now[:alert] = @project.errors.full_messages.to_sentence.presence || "Could not update project."
      render :show, status: :unprocessable_entity
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
      params.require(:project).permit(:title, :notes, :project_folder_id)
    end

    def folder_select_options(folders = nil)
      folders ||= current_user_folders.active.ordered
      folders.map { |f| [ f.breadcrumb_label, f.id ] }
    end
end

