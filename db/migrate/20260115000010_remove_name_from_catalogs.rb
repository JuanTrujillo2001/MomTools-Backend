class RemoveNameFromCatalogs < ActiveRecord::Migration[7.1]
  def change
    remove_column :catalogs, :name, :string
  end
end
