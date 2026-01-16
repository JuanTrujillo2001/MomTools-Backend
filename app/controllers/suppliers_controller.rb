class SuppliersController < ApplicationController
  def index
    suppliers = current_user.suppliers.order(:name)
    render json: suppliers.map { |s| serialize_supplier(s) }
  end

  def show
    supplier = current_user.suppliers.find(params[:id])
    render json: serialize_supplier(supplier)
  end

  def create
    supplier = current_user.suppliers.new(supplier_params)
    supplier.save!
    render json: serialize_supplier(supplier), status: :created
  end

  def update
    supplier = current_user.suppliers.find(params[:id])
    supplier.update!(supplier_params)
    render json: serialize_supplier(supplier)
  end

  def destroy
    supplier = current_user.suppliers.find(params[:id])
    supplier.destroy!
    head :no_content
  end

  private

  def supplier_params
    params.require(:supplier).permit(:name, :phone, :email)
  end

  def serialize_supplier(supplier)
    supplier.as_json(only: [:id, :name, :phone, :email, :created_at])
  end
end
