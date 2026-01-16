class AddBrandToCatalogItems < ActiveRecord::Migration[7.1]
  def change
    add_column :catalog_items, :brand, :string
  end
end
