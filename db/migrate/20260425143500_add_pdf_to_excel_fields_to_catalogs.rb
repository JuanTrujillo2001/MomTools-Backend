class AddPdfToExcelFieldsToCatalogs < ActiveRecord::Migration[7.1]
  def change
    add_column :catalogs, :pdf_to_excel_status, :string
    add_column :catalogs, :pdf_to_excel_error, :text
    add_column :catalogs, :pdf_to_excel_started_at, :datetime
    add_column :catalogs, :pdf_to_excel_finished_at, :datetime

    add_index :catalogs, :pdf_to_excel_status
  end
end
