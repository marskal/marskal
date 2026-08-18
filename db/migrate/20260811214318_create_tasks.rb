class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_enum :task_state, %w[to_do done dropped]

    create_table :tasks, id: { type: :uuid, default: -> { "uuidv7()" } } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :title, null: false
      t.text :notes
      t.enum :state, enum_type: :task_state, null: false, default: "to_do"
      t.boolean :inbox, null: false, default: true

      t.timestamps
    end

    add_index :tasks, [ :user_id, :inbox, :state ]
    add_index :tasks, [ :user_id, :state ]
  end
end
