class Supplier < ApplicationRecord
  belongs_to :user

  has_many :catalogs, dependent: :nullify
  has_many :cart_items, dependent: :destroy

  validates :name, presence: true
end
