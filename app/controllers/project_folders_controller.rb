class ProjectFoldersController < ApplicationController
  before_action :set_folder, only: %i[ show update drop activate ]

  def show
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
    if @folder.update(folder_params)
      redirect_to project_folder_path(@folder), notice: "Folder updated."
    else
      redirect_to project_folder_path(@folder), alert: @folder.errors.full_messages.to_sentence.presence || "Could not update folder."
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
      params.require(:project_folder).permit(:name, :parent_id)
    end
end
