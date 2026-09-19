# frozen_string_literal: true

class ImportBatchesController < ApplicationController
  def index
    @batches = Current.user.import_batches.order(created_at: :desc)
  end

  def new
    @batch = Current.user.import_batches.new(source: "omnifocus", channel: :file)
  end

  def create
    @batch = Current.user.import_batches.new(source: "omnifocus", channel: :file, status: :pending)
    reject_if_rate_limited
    attach_payload unless @batch.errors.any?

    if @batch.errors.empty? && @batch.save
      ImportParseJob.perform_later(@batch)
      redirect_to @batch, notice: "Reading backup…"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @batch = Current.user.import_batches.find(params[:id])
  end

  def apply
    @batch = Current.user.import_batches.find(params[:id])
    unless @batch.previewed?
      redirect_to @batch, alert: "This import is not ready to apply."
      return
    end

    @batch.applying!
    ImportApplyJob.perform_later(@batch)
    redirect_to @batch, notice: "Importing…"
  end

  private
    def reject_if_rate_limited
      recent = Current.user.import_batches.where("created_at > ?", 1.hour.ago).count
      return if recent < Imports::Limits::IMPORTS_PER_HOUR

      @batch.errors.add(:base, "Too many imports in the last hour. Try again later.")
    end

    def attach_payload
      if batch_params[:payload].present?
        @batch.payload = batch_params[:payload]
      elsif bundle_files.any?
        total = bundle_files.sum { |file| file.size.to_i }
        if total > Imports::Limits::PAYLOAD_BYTES
          @batch.errors.add(:payload, "is too large (maximum is 50 MB)")
          return
        end

        packed = Imports::BundlePackager.call(files: bundle_files, paths: bundle_paths)
        @batch.payload.attach(
          io: packed,
          filename: "OmniFocus.ofocus-backup.zip",
          content_type: "application/zip"
        )
      end
    rescue ArgumentError => e
      @batch.errors.add(:payload, e.message)
    end

    def batch_params
      params.fetch(:import_batch, {}).permit(:payload)
    end

    def bundle_files
      Array(params.dig(:import_batch, :bundle_files)).compact_blank
    end

    def bundle_paths
      Array(params.dig(:import_batch, :bundle_paths))
    end
end
