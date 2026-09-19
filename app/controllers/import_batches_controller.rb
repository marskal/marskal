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
    attach_payload

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
    def attach_payload
      if batch_params[:payload].present?
        @batch.payload = batch_params[:payload]
      elsif bundle_files.any?
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
