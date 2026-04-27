class CatalogPdfToExcelJob < ApplicationJob
  queue_as :default

  PROVIDER_OPENAI = "openai"
  PROVIDER_ADOBE = "adobe"
  PROVIDER_AUTO = "auto"

  def perform(catalog_id)
    catalog = Catalog.find_by(id: catalog_id)
    return unless catalog
    return unless catalog.file.attached?

    catalog.update!(
      pdf_to_excel_status: "processing",
      pdf_to_excel_error: nil,
      pdf_to_excel_started_at: Time.current,
      pdf_to_excel_finished_at: nil
    )

    original_filename = catalog.file.filename.to_s
    return unless File.extname(original_filename).downcase == ".pdf"

    cached_pdf_path = FileCache.fetch(catalog.file.blob)

    excel_filename = "#{File.basename(original_filename, File.extname(original_filename))}.xlsx"
    output_path = Rails.root.join("tmp", excel_filename).to_s

    provider_env = ENV.fetch("PDF_TO_EXCEL_PROVIDER", PROVIDER_OPENAI).to_s.strip.downcase
    provider = provider_env
    if provider_env == PROVIDER_AUTO
      provider = PdfToExcelProviderSelector.new(cached_pdf_path.to_s).call
      Rails.logger.info("[CatalogPdfToExcelJob] catalog_id=#{catalog_id} provider_env=#{provider_env} provider_selected=#{provider}")
    else
      Rails.logger.info("[CatalogPdfToExcelJob] catalog_id=#{catalog_id} provider_env=#{provider_env}")
    end

    generated_xlsx_path = if provider == PROVIDER_ADOBE
      AdobePdfToExcelService.new(cached_pdf_path.to_s, output_path: output_path).call
    else
      PdfToExcelService.new(cached_pdf_path.to_s, output_path: output_path).call
    end

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

    excel_cached_path = FileCache.fetch(catalog.excel_file.blob)
    workbook = Roo::Spreadsheet.open(excel_cached_path.to_s, extension: :xlsx)

    workbook.sheets.each do |sheet_name|
      normalized_sheet_name = sheet_name.to_s.strip.gsub(/\s+/, " ")
      next if normalized_sheet_name.blank?

      SheetConfig.find_or_create_by!(catalog: catalog, sheet_name: normalized_sheet_name) do |sc|
        sc.code_columns = []
        sc.description_columns = []
        sc.price_columns = []
      end
    end

    catalog.update!(pdf_to_excel_status: "done", pdf_to_excel_finished_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("[CatalogPdfToExcelJob] Error catalog_id=#{catalog_id}: #{e.class} - #{e.message}")
    begin
      Catalog.where(id: catalog_id).update_all(
        pdf_to_excel_status: "failed",
        pdf_to_excel_error: "#{e.class}: #{e.message}".to_s.first(1000),
        pdf_to_excel_finished_at: Time.current
      )
    rescue StandardError
    end
  end
end
