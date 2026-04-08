# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

org = Organization.find_or_initialize_by(name: "Stive&Barton")
org.time_zone = "Krasnoyarsk"
org.save!

admin = User.find_or_initialize_by(email: "admin@mediateca.store")
if admin.new_record?
  admin.organization = org
  admin.password = ENV.fetch("SEED_ADMIN_PASSWORD", "password123456")
  admin.password_confirmation = admin.password
  admin.save!
end
