# frozen_string_literal: true

class ButtonComponent < ApplicationComponent
  def initialize(variant: nil, type: :button, href: nil, **html)
    @variant = variant
    @type = type
    @href = href
    @html = html
  end
end
