class MakeCatalogTypeOptionalOnCatalogs < ActiveRecord::Migration[7.1]
  def change
    change_column_null :catalogs, :catalog_type_id, true
  end
end
