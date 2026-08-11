class CreateProjectFolders < ActiveRecord::Migration[8.1]
  def change
    create_enum :folder_state, %w[active dropped]

    create_table :project_folders do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.references :parent, null: true, foreign_key: { to_table: :project_folders }
      t.text :parent_path, array: true, null: false, default: []
      t.enum :state, enum_type: :folder_state, null: false, default: "active"

      t.timestamps
    end

    add_index :project_folders, [ :user_id, :state ]
    add_index :project_folders, [ :user_id, :parent_id ]

    add_reference :projects, :project_folder, null: true, foreign_key: true
    add_index :projects, [ :user_id, :project_folder_id ]
  end
end
