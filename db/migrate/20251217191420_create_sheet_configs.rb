class CreateSheetConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :sheet_configs do |t|
      t.references :catalog, null: false, foreign_key: { on_delete: :cascade }
      t.string :sheet_name, null: false

      t.string :code_columns, array: true, default: [], null: false
      t.string :description_columns, array: true, default: [], null: false
      t.string :price_columns, array: true, default: [], null: false

      t.timestamps
    end

    add_index :sheet_configs, [:catalog_id, :sheet_name], unique: true
  end
end
