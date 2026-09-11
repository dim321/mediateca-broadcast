# frozen_string_literal: true

# == Schema Information
#
# Table name: media_assets
#
#  id                :bigint           not null, primary key
#  content_kind      :string           not null
#  content_type      :string           not null
#  duration_seconds  :integer
#  metadata          :jsonb            not null
#  processing_status :string           default("pending"), not null
#  visibility        :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  organization_id   :bigint           not null
#  uploaded_by_id    :bigint
#
# Indexes
#
#  index_media_assets_on_content_type                           (content_type)
#  index_media_assets_on_organization_id                        (organization_id)
#  index_media_assets_on_organization_id_and_created_at         (organization_id,created_at DESC)
#  index_media_assets_on_organization_id_and_processing_status  (organization_id,processing_status)
#  index_media_assets_on_uploaded_by_id                         (uploaded_by_id)
#  index_media_assets_on_visibility                             (visibility)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (uploaded_by_id => users.id) ON DELETE => nullify
#
FactoryBot.define do
  factory :media_asset do
    organization
    uploaded_by { association :user, organization: organization }
    content_kind { "image" }
    content_type { "own" }
    visibility { "organization" }
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

    trait :network_neutral do
      content_type { "neutral" }
      visibility { "network" }
    end

    trait :with_mp4_file do
      content_kind { "video" }
      after(:build) do |record|
        record.file.attach(
          io: StringIO.new("fake-mp4-bytes"),
          filename: "source.mp4",
          content_type: "video/mp4"
        )
      end
    end

    trait :with_broadcast_ts do
      after(:build) do |record|
        path = Rails.root.join("spec/fixtures/files/broadcast.ts")
        record.broadcast_file.attach(
          io: File.open(path),
          filename: "source.ts",
          content_type: "video/mp2t"
        )
      end
    end
  end
end
