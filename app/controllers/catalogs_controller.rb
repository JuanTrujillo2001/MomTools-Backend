class CatalogsController < ApplicationController
  def index
    catalogs = current_user.catalogs.includes(:catalog_type)
    render json: catalogs.map { |c| serialize_catalog(c) }
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

    if catalog.file.attached?
      # Use cached file to avoid re-downloading
      cached_path = FileCache.fetch(catalog.file.blob)
      workbook = Roo::Spreadsheet.open(cached_path.to_s)

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

    render json: serialize_catalog(catalog), status: :created
  end

  def destroy
    catalog = current_user.catalogs.find(params[:id])
    # Invalidate file cache before purging
    FileCache.invalidate(catalog.file.blob) if catalog.file.attached?
    catalog.file.purge if catalog.file.attached?
    catalog.destroy!
    head :no_content
  end

  private

  def catalog_params
    params.permit(:name, :catalog_type_id, :file)
  end

  def serialize_catalog(catalog)
    catalog.as_json(only: [:id, :name, :catalog_type_id, :created_at]).merge(
      catalog_type: catalog.catalog_type.as_json(only: [:id, :name]),
      file_attached: catalog.file.attached?,
      file_name: catalog.file.attached? ? catalog.file.filename.to_s : nil
    )
  end
end
