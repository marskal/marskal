class TasksController < ApplicationController
  before_action :set_task, only: %i[ update move_to_open complete drop reopen ]

  def index
    @tasks = current_user_tasks.open_stream.recent_first
  end

  def inbox
    @tasks = current_user_tasks.inbox.to_do.recent_first
  end

  def create
    @task = current_user_tasks.new(task_create_params)
    @task.inbox = true
    @task.state = :to_do

    if @task.save
      redirect_to inbox_path, notice: "Added."
    else
      redirect_back_or_to inbox_path, alert: @task.errors.full_messages.to_sentence.presence || "Could not add task."
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
      params.require(:task).permit(:title, :notes)
    end

    def task_update_params
      params.require(:task).permit(:title, :notes)
    end

    def task_return_path
      @task.inbox? ? inbox_path : root_path
    end
end
