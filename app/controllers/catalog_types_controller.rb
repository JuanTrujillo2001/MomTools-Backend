class CatalogTypesController < ApplicationController
  def index
    catalog_types = CatalogType.order(:name)
    render json: catalog_types.as_json(only: [:id, :name, :description])
  end
end
