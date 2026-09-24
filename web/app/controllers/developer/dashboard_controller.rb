# frozen_string_literal: true

module Developer
  class DashboardController < ApplicationController
    def show
    end

    def reset_work
      Current.user.reset_captured_work!
      redirect_to developer_root_path, notice: "Folders, projects, tasks, and imports for this account are gone."
    end
  end
end
