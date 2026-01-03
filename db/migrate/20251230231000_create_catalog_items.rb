class CreateCatalogItems < ActiveRecord::Migration[7.1]
  def change
    create_table :catalog_items do |t|
      t.references :sheet_config, null: false, foreign_key: { on_delete: :cascade }
      t.string :sheet_name, null: false
      t.integer :row_number, null: false
      t.string :code, null: false
      t.text :description 
      t.decimal :price, precision: 15, scale: 2

      t.timestamps
    end

    add_index :catalog_items, :code
  end
end
