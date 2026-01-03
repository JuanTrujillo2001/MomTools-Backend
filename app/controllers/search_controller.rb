class SearchController < ApplicationController
  def index
    q = params[:q].to_s.strip
    mode = params[:mode].to_s.strip.downcase
    mode = "exact" unless %w[exact contains].include?(mode)
    limit = params[:limit].to_i
    limit = 200 if limit <= 0

    if q.blank?
      return render json: { query: q, mode: mode, limit: limit, results: [] }, status: :ok
    end

    query_normalized = q.upcase

    Rails.logger.info("[search] start q=#{q.inspect} mode=#{mode} limit=#{limit} user_id=#{current_user.id}")

    # Search in indexed catalog_items through sheet_configs
    sheet_config_ids = SheetConfig.where(catalog_id: current_user.catalogs.pluck(:id)).pluck(:id)

    items = if mode == "contains"
      CatalogItem.where(sheet_config_id: sheet_config_ids).where("code ILIKE ?", "%#{q}%")
    else
      CatalogItem.where(sheet_config_id: sheet_config_ids).where("UPPER(code) = ?", query_normalized)
    end

    # Order by price ascending (nulls last), then by sheet/row
    items = items.order(Arel.sql("COALESCE(price, 999999999) ASC"), :sheet_config_id, :sheet_name, :row_number)
                 .limit(limit)
                 .includes(sheet_config: { catalog: :catalog_type })

    results = items.map do |item|
      catalog = item.sheet_config.catalog
      {
        catalog_item_id: item.id,
        catalog_id: catalog.id,
        catalog_name: catalog.name,
        catalog_type: catalog.catalog_type&.name,
        sheet_config_id: item.sheet_config_id,
        sheet_name: item.sheet_name,
        row_number: item.row_number,
        code: item.code,
        codes: [item.code],
        descriptions: item.description.present? ? [item.description] : [],
        prices: item.price.present? ? [format('%.2f', item.price.to_f)] : []
      }
    end

    Rails.logger.info("[search] done results=#{results.size}")
    render json: { query: q, mode: mode, limit: limit, results: results }, status: :ok
  end

  def export
    q = params[:q].to_s.strip
    mode = params[:mode].to_s.strip.downcase
    mode = "exact" unless %w[exact contains].include?(mode)
    limit = params[:limit].to_i
    limit = 1000 if limit <= 0

    if q.blank?
      return head :bad_request
    end

    query_normalized = q.upcase
    sheet_config_ids = SheetConfig.where(catalog_id: current_user.catalogs.pluck(:id)).pluck(:id)

    items = if mode == "contains"
      CatalogItem.where(sheet_config_id: sheet_config_ids).where("code ILIKE ?", "%#{q}%")
    else
      CatalogItem.where(sheet_config_id: sheet_config_ids).where("UPPER(code) = ?", query_normalized)
    end

    items = items.order(Arel.sql("COALESCE(price, 999999999) ASC"), :sheet_config_id, :sheet_name, :row_number)
                 .limit(limit)
                 .includes(sheet_config: { catalog: :catalog_type })

    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Resultados") do |sheet|
      # Header row
      sheet.add_row ["Código", "Descripción", "Precio", "Catálogo", "Tipo", "Hoja", "Fila", "Archivo Original"]

      # Data rows
      items.each do |item|
        catalog = item.sheet_config.catalog
        original_filename = catalog.file.attached? ? catalog.file.filename.to_s : ''
        sheet.add_row [
          item.code,
          item.description,
          item.price.present? ? format('%.2f', item.price.to_f) : '',
          catalog.name,
          catalog.catalog_type&.name,
          item.sheet_name,
          item.row_number,
          original_filename
        ]
      end
    end

    filename = "busqueda_#{q.gsub(/[^a-zA-Z0-9]/, '_')}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.xlsx"

    send_data package.to_stream.read,
              filename: filename,
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              disposition: "attachment"
  end
end
