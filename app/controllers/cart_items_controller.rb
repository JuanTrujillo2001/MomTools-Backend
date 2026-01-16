class CartItemsController < ApplicationController
  def index
    items = current_user.cart_items
                        .includes(:supplier, catalog_item: { sheet_config: { catalog: :catalog_type } })
                        .order(:supplier_id, :created_at)

    render json: items.map { |ci| serialize_cart_item(ci) }
  end

  def export
    status_param = params[:status].to_s.strip.downcase
    status_param = "pending" if status_param.blank?

    items = current_user.cart_items
                        .includes(:supplier, catalog_item: { sheet_config: { catalog: :catalog_type } })

    if status_param == "all"
      items = items
    elsif status_param == "ordered"
      items = items.where(status: CartItem::STATUS_ORDERED)
    else
      items = items.where(status: CartItem::STATUS_PENDING)
    end

    supplier_id = params[:supplier_id].presence
    items = items.where(supplier_id: supplier_id.to_i) if supplier_id

    items = items.order(:supplier_id, :created_at)

    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Lista de compras") do |sheet|
      sheet.add_row ["Proveedor", "Código", "Descripción", "Marca", "Precio", "Cantidad", "Ordenado el", "Catálogo", "Tipo", "Hoja", "Fila"]

      items.each do |ci|
        item = ci.catalog_item
        catalog = item&.catalog
        supplier_name = ci.supplier&.name.to_s
        file_name = catalog&.file&.attached? ? catalog.file.filename.to_s : ''
        label = [supplier_name.presence, file_name.presence].compact.join(' - ')

        sheet.add_row [
          supplier_name,
          item&.code,
          item&.description,
          item&.brand,
          item&.price.present? ? format('%.2f', item.price.to_f) : '',
          ci.quantity,
          ci.ordered_at&.in_time_zone&.strftime('%Y-%m-%d %H:%M:%S'),
          label,
          catalog&.catalog_type&.name,
          item&.sheet_name,
          item&.row_number,
        ]
      end
    end

    filename = "lista_compras_#{Time.current.strftime('%Y%m%d_%H%M%S')}.xlsx"

    send_data package.to_stream.read,
              filename: filename,
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              disposition: "attachment"
  end

  def create
    ids = Array(params[:catalog_item_ids]).map(&:to_i)
    single_id = params[:catalog_item_id].presence
    ids << single_id.to_i if single_id
    ids = ids.uniq

    if ids.empty?
      return render json: { error: 'catalog_item_ids is required' }, status: :bad_request
    end

    qty = params[:quantity].to_i
    qty = 1 if qty <= 0

    created_or_updated = []

    CartItem.transaction do
      ids.each do |catalog_item_id|
        catalog_item = CatalogItem.includes(sheet_config: :catalog).find(catalog_item_id)
        catalog = catalog_item.catalog

        # Security: the catalog item must belong to the current user through the catalog
        if catalog.nil? || catalog.user_id != current_user.id
          raise ActiveRecord::RecordNotFound
        end

        supplier_id = catalog.supplier_id
        raise ActiveRecord::RecordInvalid.new(CartItem.new) if supplier_id.nil?

        cart_item = current_user.cart_items.find_or_initialize_by(catalog_item_id: catalog_item.id)

        if cart_item.persisted? && cart_item.status.to_i == CartItem::STATUS_ORDERED
          raise ActiveRecord::RecordInvalid.new(cart_item)
        end

        # Keep supplier in sync with catalog supplier
        cart_item.supplier_id = supplier_id
        cart_item.status = CartItem::STATUS_PENDING
        cart_item.ordered_at = nil

        if cart_item.persisted?
          cart_item.quantity = cart_item.quantity.to_i + qty
        else
          cart_item.quantity = qty
        end

        cart_item.save!
        created_or_updated << cart_item
      end
    end

    items = current_user.cart_items
                        .includes(:supplier, catalog_item: { sheet_config: { catalog: :catalog_type } })
                        .where(id: created_or_updated.map(&:id))
                        .order(:supplier_id, :created_at)

    render json: items.map { |ci| serialize_cart_item(ci) }, status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Catalog item not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid
    render json: { error: 'No se puede agregar: el proveedor es obligatorio y/o el item ya está ordenado' }, status: :unprocessable_entity
  end

  def update
    cart_item = current_user.cart_items.find(params[:id])

    if cart_item.status.to_i == CartItem::STATUS_ORDERED
      return render json: { error: 'Este item está ordenado y no se puede modificar' }, status: :unprocessable_entity
    end

    status_param = params[:status]
    if status_param.present?
      next_status = status_param.to_i
      unless [CartItem::STATUS_PENDING, CartItem::STATUS_ORDERED].include?(next_status)
        return render json: { error: 'status inválido' }, status: :unprocessable_entity
      end
      if next_status == CartItem::STATUS_ORDERED
        cart_item.update!(status: next_status, ordered_at: Time.current)
      else
        cart_item.update!(status: next_status)
      end
      return render json: serialize_cart_item(cart_item)
    end

    quantity = params[:quantity].to_i
    return render json: { error: 'quantity must be > 0' }, status: :unprocessable_entity if quantity <= 0

    cart_item.update!(quantity: quantity)
    render json: serialize_cart_item(cart_item)
  end

  def destroy
    cart_item = current_user.cart_items.find(params[:id])

    if cart_item.status.to_i == CartItem::STATUS_ORDERED
      return render json: { error: 'Este item está ordenado y no se puede eliminar' }, status: :unprocessable_entity
    end

    cart_item.destroy!
    head :no_content
  end

  private

  def serialize_cart_item(cart_item)
    catalog_item = cart_item.catalog_item
    catalog = catalog_item.catalog

    {
      id: cart_item.id,
      quantity: cart_item.quantity,
      status: cart_item.status,
      ordered_at: cart_item.ordered_at,
      supplier_id: cart_item.supplier_id,
      supplier: cart_item.supplier.as_json(only: [:id, :name, :phone, :email]),
      catalog_item: {
        id: catalog_item.id,
        code: catalog_item.code,
        description: catalog_item.description,
        price: catalog_item.price,
        brand: catalog_item.brand,
        sheet_name: catalog_item.sheet_name,
        row_number: catalog_item.row_number,
        catalog_id: catalog&.id,
        catalog_type: catalog&.catalog_type&.as_json(only: [:id, :name]),
        file_name: catalog&.file&.attached? ? catalog.file.filename.to_s : nil,
      },
      created_at: cart_item.created_at
    }
  end
end
