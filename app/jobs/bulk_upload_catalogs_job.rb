class BulkUploadCatalogsJob < ApplicationJob
  queue_as :default

  def perform(bulk_upload_id, items_data)
    bulk_upload = BulkUpload.find(bulk_upload_id)
    user = bulk_upload.user
    bulk_upload_dir = Rails.root.join("tmp", "bulk_uploads", bulk_upload_id.to_s)
    
    bulk_upload.update!(status: 'processing')
    results = []

    items_data.each_with_index do |item_data, idx|
      begin
        supplier_id = item_data['supplier_id']
        file_info = item_data['file']

        catalog = user.catalogs.new(supplier_id: supplier_id)
        
        # Read file content into memory to avoid closed stream issues
        temp_path = file_info['path']
        file_content = File.binread(temp_path)
        
        catalog.file.attach(
          io: StringIO.new(file_content),
          filename: file_info['filename'],
          content_type: file_info['content_type'],
          key: "catalogs/#{user.id}/#{SecureRandom.uuid}_#{file_info['filename']}"
        )
        
        catalog.save!
        process_catalog_file!(catalog)

        results << { index: idx, success: true, catalog_id: catalog.id }
      rescue => e
        results << { index: idx, success: false, error: e.message }
      end

      bulk_upload.update!(processed: idx + 1, results: results)
    end

    final_status = results.all? { |r| r[:success] } ? 'completed' : 'completed'
    bulk_upload.update!(status: final_status)
  rescue => e
    bulk_upload.update!(status: 'failed', results: [{ error: e.message }]) if bulk_upload
    raise
  ensure
    # Clean up entire bulk upload directory
    FileUtils.rm_rf(bulk_upload_dir) if bulk_upload_dir && Dir.exist?(bulk_upload_dir)
  end

  private

  def process_catalog_file!(catalog)
    return unless catalog.file.attached?

    cached_path = FileCache.fetch(catalog.file.blob)
    file_ext = File.extname(cached_path.to_s).downcase
    source_path = if file_ext == ".pdf"
      original_filename = catalog.file.filename.to_s
      excel_filename = "#{File.basename(original_filename, File.extname(original_filename))}.xlsx"
      output_path = Rails.root.join("tmp", excel_filename).to_s

      generated_xlsx_path = PdfToExcelService.new(cached_path.to_s, output_path: output_path).call

      pdf_key = catalog.file.blob.key.to_s
      excel_key = pdf_key.sub(/\.pdf\z/i, ".xlsx")
      excel_key = "#{pdf_key}.xlsx" if excel_key == pdf_key

      File.open(generated_xlsx_path, "rb") do |f|
        catalog.excel_file.attach(
          io: f,
          filename: excel_filename,
          content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          key: excel_key
        )
      end

      FileCache.fetch(catalog.excel_file.blob).to_s
    else
      cached_path.to_s
    end

    original_ext = File.extname(catalog.file.filename.to_s).downcase.strip
    
    Rails.logger.info("[BulkUploadCatalogsJob] Processing file: #{catalog.file.filename}, extension: '#{original_ext}'")
    
    # Always pass extension explicitly to Roo
    ext_sym = original_ext.gsub('.', '').to_sym if original_ext.present?
    
    Rails.logger.info("[BulkUploadCatalogsJob] Extension symbol: #{ext_sym.inspect}")
    
    workbook = if ext_sym.present?
      Roo::Spreadsheet.open(source_path.to_s, extension: ext_sym)
    else
      Roo::Spreadsheet.open(source_path.to_s)
    end

    workbook.sheets.each do |sheet_name|
      normalized_sheet_name = sheet_name.to_s.strip.gsub(/\s+/, ' ')
      next if normalized_sheet_name.blank?

      SheetConfig.find_or_create_by!(catalog: catalog, sheet_name: normalized_sheet_name) do |sc|
        sc.code_columns = []
        sc.description_columns = []
        sc.price_columns = []
      end
    end
  end
end
