class CreateCatalogs < ActiveRecord::Migration[7.1]
  def change
    create_table :catalogs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :catalog_type, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end
  end
end
