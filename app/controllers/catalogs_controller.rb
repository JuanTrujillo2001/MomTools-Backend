class CatalogsController < ApplicationController
  def index
    page = params[:page].to_i
    page = 1 if page < 1
    per_page = params[:per_page].to_i
    per_page = 20 if per_page < 1 || per_page > 100

    catalogs = current_user.catalogs
                          .left_joins(:supplier)
                          .select('catalogs.*, suppliers.name as supplier_name')
                          .includes(file_attachment: :blob, excel_file_attachment: :blob)
                          .order(created_at: :desc)
                          .page(page)
                          .per(per_page)

    render json: {
      catalogs: catalogs.map { |c| serialize_catalog_light(c) },
      pagination: {
        current_page: catalogs.current_page,
        total_pages: catalogs.total_pages,
        total_count: catalogs.total_count,
        per_page: per_page,
        has_more: catalogs.current_page < catalogs.total_pages
      }
    }
  end

  def show
    catalog = current_user.catalogs.find(params[:id])
    render json: serialize_catalog(catalog)
  end

  def create
    catalog = current_user.catalogs.new(catalog_params)

    if params[:file].present?
      catalog.file.attach(
        io: params[:file].tempfile,
        filename: params[:file].original_filename,
        content_type: params[:file].content_type,
        key: "catalogs/#{current_user.id}/#{SecureRandom.uuid}_#{params[:file].original_filename}"
      )
    end

    catalog.save!

    process_catalog_file!(catalog)

    render json: serialize_catalog(catalog), status: :created
  end

  def bulk_create
    items_param = params[:items]
    items = if items_param.is_a?(ActionController::Parameters) || items_param.is_a?(Hash)
      raw = items_param.is_a?(ActionController::Parameters) ? items_param.to_unsafe_h : items_param
      raw.sort_by { |k, _| k.to_i }.map { |_, v| v }
    else
      Array(items_param)
    end

    if items.empty?
      return render json: { error: 'items is required' }, status: :bad_request
    end

    # Create BulkUpload record
    bulk_upload = current_user.bulk_uploads.create!(
      total: items.size,
      processed: 0,
      status: 'pending',
      results: []
    )

    # Prepare items data for background job (save files to persistent temp)
    bulk_upload_dir = Rails.root.join("tmp", "bulk_uploads", bulk_upload.id.to_s)
    FileUtils.mkdir_p(bulk_upload_dir)

    items_data = items.map.with_index do |item, idx|
      supplier_id = item[:supplier_id].presence || item['supplier_id'].presence
      file_param = item[:file] || item['file']

      raise ActionController::BadRequest, 'supplier_id is required' if supplier_id.blank?
      raise ActionController::BadRequest, 'file is required' if file_param.blank?

      # Save uploaded file to persistent temp location
      ext = File.extname(file_param.original_filename)
      temp_path = bulk_upload_dir.join("#{idx}_#{SecureRandom.hex(4)}#{ext}")
      
      File.open(temp_path, 'wb') do |f|
        f.write(file_param.read)
      end

      {
        'supplier_id' => supplier_id,
        'file' => {
          'path' => temp_path.to_s,
          'filename' => file_param.original_filename,
          'content_type' => file_param.content_type
        }
      }
    end

    # Enqueue background job
    BulkUploadCatalogsJob.perform_later(bulk_upload.id, items_data)

    render json: { 
      bulk_upload_id: bulk_upload.id,
      status: bulk_upload.status,
      total: bulk_upload.total,
      processed: bulk_upload.processed
    }, status: :accepted
  end

  def update
    catalog = current_user.catalogs.find(params[:id])
    old_supplier_id = catalog.supplier_id
    catalog.update!(catalog_update_params)

    if old_supplier_id != catalog.supplier_id
      pending_items = current_user.cart_items
                                 .joins(catalog_item: { sheet_config: :catalog })
                                 .where(catalogs: { id: catalog.id }, status: CartItem::STATUS_PENDING)

      if catalog.supplier_id.present?
        pending_items.update_all(supplier_id: catalog.supplier_id)
      else
        pending_items.destroy_all
      end
    end
    render json: serialize_catalog(catalog)
  end

  def destroy
    catalog = current_user.catalogs.find(params[:id])
    original_blob = catalog.file.attached? ? catalog.file.blob : nil
    excel_blob = catalog.excel_file.attached? ? catalog.excel_file.blob : nil

    ActiveRecord::Base.transaction do
      current_user.cart_items
                  .joins(catalog_item: { sheet_config: :catalog })
                  .where(catalogs: { id: catalog.id })
                  .delete_all

      catalog.destroy!
    end

    FileCache.invalidate(original_blob) if original_blob
    FileCache.invalidate(excel_blob) if excel_blob
    original_blob&.purge
    excel_blob&.purge
    head :no_content
  end

  def download
    catalog = current_user.catalogs.find(params[:id])
    raise ActiveRecord::RecordNotFound, "Catalog file not attached" unless catalog.file.attached?

    format = params[:format].to_s.strip.downcase
    cached_original_path = FileCache.fetch(catalog.file.blob)
    original_ext = File.extname(cached_original_path.to_s).downcase

    if format == "pdf"
      raise ActionController::BadRequest, "Catalog is not a PDF" unless original_ext == ".pdf"

      send_file cached_original_path.to_s,
                filename: catalog.file.filename.to_s,
                type: catalog.file.blob.content_type,
                disposition: "attachment"
      return
    end

    if original_ext == ".pdf"
      excel_blob = if catalog.excel_file.attached?
        catalog.excel_file.blob
      else
        original_filename = catalog.file.filename.to_s
        excel_filename = "#{File.basename(original_filename, File.extname(original_filename))}.xlsx"
        output_path = Rails.root.join("tmp", excel_filename).to_s

        generated_xlsx_path = PdfToExcelService.new(cached_original_path.to_s, output_path: output_path).call

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

        catalog.excel_file.blob
      end

      excel_cached_path = FileCache.fetch(excel_blob)
      send_file excel_cached_path.to_s,
                filename: excel_blob.filename.to_s,
                type: excel_blob.content_type,
                disposition: "attachment"
      return
    end

    send_file cached_original_path.to_s,
              filename: catalog.file.filename.to_s,
              type: catalog.file.blob.content_type,
              disposition: "attachment"
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
    
    # Always pass extension explicitly to Roo
    ext_sym = original_ext.gsub('.', '').to_sym if original_ext.present?
    
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

  def catalog_params
    params.permit(:supplier_id, :file)
  end

  def catalog_update_params
    params.require(:catalog).permit(:supplier_id)
  end

  def serialize_catalog(catalog)
    catalog.as_json(only: [:id, :supplier_id, :created_at]).merge(
      supplier: catalog.supplier&.as_json(only: [:id, :name, :phone, :email]),
      file_attached: catalog.file.attached?,
      file_name: catalog.file.attached? ? catalog.file.filename.to_s : nil,
      excel_file_attached: catalog.excel_file.attached?,
      excel_file_name: catalog.excel_file.attached? ? catalog.excel_file.filename.to_s : nil
    )
  end

  def serialize_catalog_light(catalog)
    catalog.as_json(only: [:id, :supplier_id, :created_at]).merge(
      supplier: catalog.supplier_name ? { name: catalog.supplier_name } : nil,
      file_attached: catalog.file.attached?,
      file_name: catalog.file.attached? ? catalog.file.filename.to_s : nil,
      excel_file_attached: catalog.excel_file.attached?,
      excel_file_name: catalog.excel_file.attached? ? catalog.excel_file.filename.to_s : nil
    )
  end
end
