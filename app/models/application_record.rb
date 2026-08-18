class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # UUIDv7 is time-ordered, but fixtures (and other clients) may supply any UUID.
  # Recency is created_at, not id (ADR 0011).
  self.implicit_order_column = "created_at"
end
