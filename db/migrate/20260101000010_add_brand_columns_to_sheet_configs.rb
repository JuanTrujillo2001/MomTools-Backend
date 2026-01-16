class AddBrandColumnsToSheetConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :sheet_configs, :brand_columns, :string, array: true, default: [], null: false
  end
end
