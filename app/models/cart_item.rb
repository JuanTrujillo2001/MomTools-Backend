class CartItem < ApplicationRecord
  STATUS_PENDING = 0
  STATUS_ORDERED = 1

  belongs_to :user
  belongs_to :supplier
  belongs_to :catalog_item

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: [STATUS_PENDING, STATUS_ORDERED] }
end
