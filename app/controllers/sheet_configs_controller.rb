class SheetConfigsController < ApplicationController
  def index
    catalog = current_user.catalogs.find(params[:catalog_id])
    sheet_configs = catalog.sheet_configs.order(:sheet_name)
    render json: sheet_configs.map { |sc| serialize_sheet_config(sc) }
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
      price_columns: []
    )
  end

  def serialize_sheet_config(sheet_config)
    sheet_config.as_json(only: [:id, :catalog_id, :sheet_name, :code_columns, :description_columns, :price_columns, :created_at])
  end
end
