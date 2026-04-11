class RemoveCatalogTypes < ActiveRecord::Migration[7.1]
  def change
    remove_reference :catalogs, :catalog_type, foreign_key: true, index: true
    drop_table :catalog_types
  end
end
