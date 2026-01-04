# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

user = User.find_or_initialize_by(email: "juantrujillo.usa@gmail.com")
user.name = "Juan Jose Trujillo"
user.password = "Juanj200"
user.password_confirmation = "Juanj200"
user.save!

other = User.find_or_initialize_by(email: "Fannyr127@hotmail.com")
other.name = "Fanny Rodriguez"
other.password = "Juanj2001"
other.password_confirmation = "Juanj2001"
other.save!

CatalogType.find_or_create_by!(name: "xlsx") do |ct|
  ct.description = "Excel"
end
