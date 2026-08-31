# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

org_1 = Organization.find_or_initialize_by(name: "Advertising company")
org_1.time_zone = "Krasnoyarsk"
org_1.kind = :operator
org_1.save!

org_2 = Organization.find_or_initialize_by(name: "Аллея")
org_2.time_zone = "Krasnoyarsk"
org_2.kind = :client
org_2.save!

org_3 = Organization.find_or_initialize_by(name: "Командор")
org_3.time_zone = "Krasnoyarsk"
org_3.kind = :client
org_3.save!

admin = User.find_or_initialize_by(email: "admin@mediateca.store")
if admin.new_record?
  admin.organization = org_1
  admin.role = :administrator
  admin.password = ENV.fetch("SEED_ADMIN_PASSWORD", "password123456")
  admin.password_confirmation = admin.password
  admin.save!
end
