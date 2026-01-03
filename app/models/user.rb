class User < ApplicationRecord
  has_secure_password

  has_many :catalogs, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  before_validation do
    self.email = email.to_s.strip.downcase
  end
end
