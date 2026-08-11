class TasksController < ApplicationController
  before_action :set_task, only: %i[ update move_to_open complete drop reopen ]

  def index
    @tasks = current_user_tasks.open_stream.includes(:project).recent_first
  end

  def inbox
    @tasks = current_user_tasks.inbox.to_do.recent_first
  end

  def create
    @task = current_user_tasks.new(task_create_params)
    @task.state = :to_do
    apply_create_placement!(@task)

    if @task.save
      redirect_to task_create_redirect_path(@task), notice: "Added."
    else
      redirect_back_or_to fallback_create_path, alert: @task.errors.full_messages.to_sentence.presence || "Could not add task."
    end
  end

  def update
    if @task.update(task_update_params)
      redirect_back_or_to task_return_path, notice: "Updated."
    else
      redirect_back_or_to task_return_path, alert: @task.errors.full_messages.to_sentence.presence || "Could not update task."
    end
  end

  def move_to_open
    @task.move_to_open!
    redirect_back_or_to inbox_path, notice: "Moved to open tasks."
  end

  def complete
    @task.complete!
    redirect_back_or_to task_return_path, notice: "Done."
  end

  def drop
    @task.drop!
    redirect_back_or_to task_return_path, notice: "Dropped."
  end

  def reopen
    @task.reopen!
    redirect_back_or_to task_return_path, notice: "Reopened."
  end

  private
    def current_user_tasks
      Current.user.tasks
    end

    def set_task
      @task = current_user_tasks.find(params[:id])
    end

    def task_create_params
      params.require(:task).permit(:title, :notes, :project_id)
    end

    def task_update_params
      params.require(:task).permit(:title, :notes, :project_id)
    end

    # Global add → inbox. Add under a project → already organized (not inbox).
    def apply_create_placement!(task)
      if task.project_id.present?
        task.inbox = false
      else
        task.inbox = true
        task.project_id = nil
      end
    end

    def task_create_redirect_path(task)
      if task.project_id.present?
        project_path(task.project_id)
      else
        inbox_path
      end
    end

    def fallback_create_path
      project_id = params.dig(:task, :project_id)
      project_id.present? ? project_path(project_id) : inbox_path
    rescue ActionController::UrlGenerationError
      inbox_path
    end

    def task_return_path
      return inbox_path if @task.inbox?
      return project_path(@task.project_id) if @task.project_id.present?

      root_path
    end
end
