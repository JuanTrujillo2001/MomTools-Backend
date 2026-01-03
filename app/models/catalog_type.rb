class CatalogType < ApplicationRecord
  has_many :catalogs, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation do
    self.name = name.to_s.strip.downcase
  end
end
