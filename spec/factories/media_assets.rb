# frozen_string_literal: true

FactoryBot.define do
  factory :media_asset do
    organization
    uploaded_by { association :user, organization: organization }
    content_kind { "image" }
    processing_status { "pending" }
    metadata { {} }

    trait :with_png_file do
      after(:build) do |record|
        path = Rails.root.join("spec/fixtures/files/1x1.png")
        record.file.attach(
          io: File.open(path),
          filename: "1x1.png",
          content_type: "image/png"
        )
      end
    end

    trait :ready do
      processing_status { "ready" }
    end
  end
end
