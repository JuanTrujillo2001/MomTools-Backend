class Catalog < ApplicationRecord
  belongs_to :user
  belongs_to :catalog_type

  has_one_attached :file
  has_many :sheet_configs, dependent: :delete_all  # CASCADE in DB handles this
  has_many :catalog_items, through: :sheet_configs

  validates :name, presence: true
end
