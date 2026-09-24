class TasksController < ApplicationController
  before_action :set_task, only: %i[ show update move_to_open complete drop reopen ]

  def index
    @tasks = current_user_tasks.open_stream.includes(:project).recent_first
  end

  def inbox
    @tasks = current_user_tasks.inbox.to_do.includes(:project).recent_first
  end

  def show
    unless turbo_frame_request?
      redirect_to task_return_path(task: @task.id)
      return
    end

    load_inspector_extras
    render layout: false
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
    updated = @task.update(task_update_params)
    @task.reload if updated
    load_inspector_extras

    if updated
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to task_return_path(task: @task.id), notice: "Updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
        format.html { redirect_to task_return_path(task: @task.id), alert: @task.errors.full_messages.to_sentence.presence || "Could not update task." }
      end
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
      attrs = params.require(:task).permit(:title, :notes, :project_id, :inbox, :state)
      attrs[:project_id] = nil if attrs.key?(:project_id) && attrs[:project_id].blank?
      attrs
    end

    def load_inspector_extras
      @projects = inspector_project_options(@task)
      @list_context = params[:list_context].presence_in(%w[open inbox project]) || "open"
      @list_project_id = params[:list_project_id].presence
    end

    def inspector_project_options(task)
      projects = Current.user.projects.open_stream.order(:title).to_a
      current = task.project
      if current && current.user_id == Current.user.id && projects.none? { |project| project.id == current.id }
        projects.unshift(current)
      end
      projects
    end

    def inspector_row_visible?
      case @list_context
      when "inbox"
        @task.inbox? && @task.to_do?
      when "project"
        @task.to_do? && !@task.inbox? && @task.project_id.to_s == @list_project_id.to_s
      when "open"
        @task.to_do? && !@task.inbox?
      else
        true
      end
    end
    helper_method :inspector_row_visible?

    def inspector_row_context
      (@list_context.presence || "open").to_sym
    end
    helper_method :inspector_row_context

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

    def task_return_path(**extra)
      if @task.inbox?
        inbox_path(extra)
      elsif @task.project_id.present?
        project_path(@task.project_id, extra)
      else
        root_path(extra)
      end
    end
end
