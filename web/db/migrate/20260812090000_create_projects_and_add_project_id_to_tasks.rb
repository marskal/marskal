class CreateProjectsAndAddProjectIdToTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :projects, id: { type: :uuid, default: -> { "uuidv7()" } } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :title, null: false
      t.text :notes
      t.enum :state, enum_type: :task_state, null: false, default: "to_do"

      t.timestamps
    end

    add_index :projects, [ :user_id, :state ]

    add_reference :tasks, :project, type: :uuid, null: true, foreign_key: true
    add_index :tasks, [ :user_id, :project_id ]
  end
end
