# frozen_string_literal: true

class ImportBatch < ApplicationRecord
  MAX_PAYLOAD_BYTES = Imports::Limits::PAYLOAD_BYTES

  belongs_to :user
  has_many :import_items, dependent: :destroy
  has_one_attached :payload

  enum :status, {
    pending: "pending",
    previewed: "previewed",
    applying: "applying",
    applied: "applied",
    failed: "failed"
  }, validate: true

  enum :channel, {
    file: "file",
    oauth: "oauth"
  }, validate: true

  validates :source, presence: true
  validate :payload_present_for_file_channel
  validate :payload_size_within_limit

  def filename
    payload.attached? ? payload.filename.to_s : ""
  end

  private
    def payload_present_for_file_channel
      return unless file?
      return if payload.attached?

      errors.add(:payload, "must be attached")
    end

    def payload_size_within_limit
      return unless payload.attached?
      return if payload.byte_size <= MAX_PAYLOAD_BYTES

      errors.add(:payload, "is too large (maximum is 50 MB)")
    end
end
