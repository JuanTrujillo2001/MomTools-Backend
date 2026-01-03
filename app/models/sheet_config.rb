class SheetConfig < ApplicationRecord
  belongs_to :catalog
  has_many :catalog_items, dependent: :delete_all  # CASCADE in DB handles this

  validates :sheet_name, presence: true

  before_validation :normalize_sheet_name
  before_validation :normalize_columns

  private

  def normalize_sheet_name
    self.sheet_name = sheet_name.to_s.strip.gsub(/\s+/, ' ')
  end

  def normalize_columns
    self.code_columns = Array(code_columns).map { |v| v.to_s.strip.upcase }.reject(&:blank?)
    self.description_columns = Array(description_columns).map { |v| v.to_s.strip.upcase }.reject(&:blank?)
    self.price_columns = Array(price_columns).map { |v| v.to_s.strip.upcase }.reject(&:blank?)
  end
end
