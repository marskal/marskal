# frozen_string_literal: true

class FlashComponent < ApplicationComponent
  def initialize(notice: nil, alert: nil)
    @notice = notice
    @alert = alert
  end

  def render?
    @notice.present? || @alert.present?
  end
end
