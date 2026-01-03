class CreateCatalogTypes < ActiveRecord::Migration[7.1]
  def change
    create_table :catalog_types do |t|
      t.string :name, null: false
      t.string :description

      t.timestamps
    end

    add_index :catalog_types, :name, unique: true
  end
end
