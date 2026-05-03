class SheetConfigsController < ApplicationController
  def index
    catalog = current_user.catalogs.find(params[:catalog_id])
    sheet_configs = catalog.sheet_configs.order(:sheet_name)
    render json: sheet_configs.map { |sc| serialize_sheet_config(sc) }
  end

  def bulk_update
    catalog = current_user.catalogs.find(params[:catalog_id])
    items = bulk_sheet_configs_params
    index_results = {}

    SheetConfig.transaction do
      items.each do |item|
        sheet_config = catalog.sheet_configs.find(item[:id])
        attrs = item.except(:id)
        sheet_config.assign_attributes(attrs)

        next unless sheet_config.changed?

        sheet_config.save!

        code_cols = Array(sheet_config.code_columns)
        price_cols = Array(sheet_config.price_columns)

        if code_cols.any? && price_cols.empty?
          raise ArgumentError, "Sheet '#{sheet_config.sheet_name}': price columns required"
        end
        if price_cols.any? && code_cols.empty?
          raise ArgumentError, "Sheet '#{sheet_config.sheet_name}': code columns required"
        end

        if code_cols.any? && price_cols.any?
          result = CatalogIndexer.new(sheet_config).call
          index_results[sheet_config.id] = result
          raise StandardError, (result[:error].presence || 'Indexing failed') unless result[:success]
        end
      end
    end

    sheet_configs = catalog.sheet_configs.order(:sheet_name)
    render json: {
      sheet_configs: sheet_configs.map { |sc| serialize_sheet_config(sc) },
      index_results: index_results,
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'SheetConfig not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    catalog = current_user.catalogs.find(params[:catalog_id])
    sheet_config = catalog.sheet_configs.new(sheet_config_params)
    sheet_config.save!
    index_result = CatalogIndexer.new(sheet_config).call
    render json: serialize_sheet_config(sheet_config).merge(index_result: index_result), status: :created
  end

  def update
    catalog = current_user.catalogs.find(params[:catalog_id])
    sheet_config = catalog.sheet_configs.find(params[:id])
    sheet_config.update!(sheet_config_params)
    index_result = CatalogIndexer.new(sheet_config).call
    render json: serialize_sheet_config(sheet_config).merge(index_result: index_result)
  end

  def destroy
    catalog = current_user.catalogs.find(params[:catalog_id])
    sheet_config = catalog.sheet_configs.find(params[:id])
    sheet_config.destroy!
    head :no_content
  end

  private

  def sheet_config_params
    params.require(:sheet_config).permit(
      :sheet_name,
      code_columns: [],
      description_columns: [],
      price_columns: [],
      brand_columns: []
    )
  end

  def bulk_sheet_configs_params
    params.require(:sheet_configs).map do |p|
      p.permit(
        :id,
        :sheet_name,
        code_columns: [],
        description_columns: [],
        price_columns: [],
        brand_columns: []
      ).to_h
    end
  end

  def serialize_sheet_config(sheet_config)
    sheet_config.as_json(only: [:id, :catalog_id, :sheet_name, :code_columns, :description_columns, :price_columns, :brand_columns, :created_at])
  end
end
