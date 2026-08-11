class ProjectsController < ApplicationController
  before_action :set_project, only: %i[ show update complete drop reopen ]

  def index
    @projects = current_user_projects.open_stream.recent_first
    @project = Project.new
  end

  def show
    @tasks = @project.open_tasks
    @task = Task.new(project: @project)
  end

  def create
    @project = current_user_projects.new(project_params)
    @project.state = :to_do

    if @project.save
      redirect_to @project, notice: "Project added."
    else
      @projects = current_user_projects.open_stream.recent_first
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

    def set_project
      @project = current_user_projects.find(params[:id])
    end

    def project_params
      params.require(:project).permit(:title, :notes)
    end
end
