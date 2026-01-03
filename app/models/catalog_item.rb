class CatalogItem < ApplicationRecord
  belongs_to :sheet_config
  has_one :catalog, through: :sheet_config

  validates :sheet_name, presence: true
  validates :row_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :code, presence: true

  # Normalize code to uppercase before saving
  before_validation :normalize_code

  private

  def normalize_code
    self.code = code.to_s.strip.upcase if code.present?
  end
end
