class ChangeCatalogsNameNull < ActiveRecord::Migration[7.1]
  def up
    change_column_null :catalogs, :name, true
  end

  def down
    execute <<~SQL
      UPDATE catalogs
      SET name = COALESCE(NULLIF(name, ''), 'CATALOGO')
      WHERE name IS NULL OR name = ''
    SQL

    change_column_null :catalogs, :name, false
  end
end
