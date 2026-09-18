# frozen_string_literal: true

class ApplicationComponent < ViewComponent::Base
  include ApplicationHelper

  class << self
    def scope_class
      @scope_class ||= name.demodulize
        .delete_suffix("Component")
        .underscore
        .dasherize
    end

    attr_writer :scope_class

    # Root class plus optional `--modifier` tokens.
    # `ButtonComponent.classes(:primary)` => `"button button--primary"`.
    def classes(*modifiers, extra: nil)
      tokens = [ scope_class ]
      modifiers.flatten.compact.each do |mod|
        tokens << "#{scope_class}--#{mod.to_s.dasherize}"
      end
      tokens.concat(Array(extra))
      tokens.join(" ")
    end
  end

  delegate :scope_class, to: :class

  def root_class(*modifiers, extra: nil)
    self.class.classes(*modifiers, extra: extra)
  end
end
