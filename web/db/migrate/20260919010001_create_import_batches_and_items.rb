# frozen_string_literal: true

class CreateImportBatchesAndItems < ActiveRecord::Migration[8.1]
  def change
    create_enum :import_batch_status, %w[pending previewed applying applied failed]
    create_enum :import_channel, %w[file oauth]
    create_enum :import_item_kind, %w[folder project task]

    create_table :import_batches, id: { type: :uuid, default: -> { "uuidv7()" } } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :source, null: false
      t.enum :channel, enum_type: :import_channel, null: false, default: "file"
      t.enum :status, enum_type: :import_batch_status, null: false, default: "pending"
      t.jsonb :stats, null: false, default: {}
      t.text :error_message
      t.string :external_account

      t.timestamps
    end

    add_index :import_batches, [ :user_id, :created_at ]

    create_table :import_items, id: { type: :uuid, default: -> { "uuidv7()" } } do |t|
      t.references :import_batch, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :source, null: false
      t.enum :kind, enum_type: :import_item_kind, null: false
      t.string :source_id, null: false
      t.references :project_folder, type: :uuid, null: true, foreign_key: true
      t.references :project, type: :uuid, null: true, foreign_key: true
      t.references :task, type: :uuid, null: true, foreign_key: true
      t.jsonb :extras, null: false, default: {}

      t.timestamps
    end

    add_index :import_items, [ :user_id, :source, :source_id ], unique: true
    add_index :import_items, [ :import_batch_id, :kind ]
  end
end
