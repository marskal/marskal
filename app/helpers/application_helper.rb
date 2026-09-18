module ApplicationHelper
  # Class string for `<button>`, `button_to`, and `form.submit`.
  def btn(*variants)
    ButtonComponent.classes(*variants)
  end
end
