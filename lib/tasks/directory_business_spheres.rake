# frozen_string_literal: true

require "csv"

namespace :directory do
  namespace :business_spheres do
    desc "Import business spheres from lib/data/business_spheres.csv (idempotent)"
    task import: :environment do
      path = Rails.root.join("lib/data/business_spheres.csv")
      unless path.exist?
        abort "File not found: #{path}"
      end

      created = 0
      skipped = 0

      CSV.foreach(path, headers: true) do |row|
        name = row["name"].to_s.strip
        next if name.blank?

        existing = Directory::BusinessSphere.where("lower(name) = ?", name.downcase).exists?
        if existing
          skipped += 1
          next
        end

        Directory::BusinessSphere.create!(name: name)
        created += 1
      end

      puts "Business spheres import complete: #{created} created, #{skipped} already present"
    end
  end
end
