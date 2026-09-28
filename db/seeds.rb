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

org_4 = Organization.find_or_initialize_by(name: "Вираж")
org_4.time_zone = "Krasnoyarsk"
org_4.kind = :client
org_4.save!

seed_password = ENV.fetch("SEED_ADMIN_PASSWORD", "password123456")

[
  {
    email: "admin@mediateca.store",
    organization: org_1,
    role: :administrator,
    first_name: "Вениамин",
    last_name: "Хомяков",
    job_title: "Главный админ",
    location: "Красноярск",
    phone: "89029234241",
    telegram: "@Tunturimies"
  },
  {
    email: "manager@comandor.com",
    organization: org_3,
    role: :manager
  },
  {
    email: "manager@viraz.com",
    organization: org_4,
    role: :manager,
    first_name: "Аглая",
    last_name: "Перепетюлькина",
    job_title: "Старший менеджер",
    location: "Абакан",
    phone: "89992031122"
  },
  {
    email: "traffic@mediateca.store",
    organization: org_1,
    role: :traffic_manager,
    first_name: "Traffic",
    last_name: "Manager"
  },
  {
    email: "traffic-manager@viraz.com",
    organization: org_4,
    role: :traffic_manager,
    first_name: "Дормидонт",
    last_name: "Ферапонтов",
    job_title: "Траффик менеджер",
    location: "Красноярск"
  },
  {
    email: "manager@mediateca.store",
    organization: org_1,
    role: :manager,
    first_name: "Арнольд",
    last_name: "Шварценеггер",
    job_title: "менеджер по продажам",
    location: "Красноярск"
  }
].each do |attrs|
  user = User.find_or_initialize_by(email: attrs.fetch(:email))
  next unless user.new_record?

  user.assign_attributes(attrs.except(:email))
  user.password = seed_password
  user.password_confirmation = seed_password
  user.save!
end
