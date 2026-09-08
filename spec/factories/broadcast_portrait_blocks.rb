# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_portrait_blocks
#
#  id                    :bigint           not null, primary key
#  kind                  :string           not null
#  pick_strategy         :string
#  position              :integer          not null
#  time_of_day           :time
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  broadcast_portrait_id :bigint           not null
#  rotation_id           :bigint
#  service_theme_id      :bigint
#
# Indexes
#
#  index_broadcast_portrait_blocks_on_broadcast_portrait_id  (broadcast_portrait_id)
#  index_broadcast_portrait_blocks_on_portrait_and_position  (broadcast_portrait_id,position) UNIQUE
#  index_broadcast_portrait_blocks_on_rotation_id            (rotation_id)
#  index_broadcast_portrait_blocks_on_service_theme_id       (service_theme_id)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_portrait_id => broadcast_portraits.id) ON DELETE => cascade
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (service_theme_id => service_themes.id) ON DELETE => restrict
#
FactoryBot.define do
  factory :broadcast_portrait_block do
    broadcast_portrait
    sequence(:position) { |n| n }
    kind { "commercial" }

    trait :commercial do
      kind { "commercial" }
      rotation { nil }
      service_theme { nil }
      pick_strategy { nil }
      time_of_day { nil }
    end

    trait :filler do
      kind { "filler" }
      rotation
      pick_strategy { "sequential" }
      time_of_day { nil }
    end

    trait :insertion do
      kind { "insertion" }
      rotation
      pick_strategy { "sequential" }
      time_of_day { "12:00" }
    end

    trait :service_header_start do
      kind { "service_header_start" }
      rotation { service_theme&.header_start_rotation }
      pick_strategy { service_theme.present? ? "sequential" : nil }
      time_of_day { nil }
    end

    trait :service_header_end do
      kind { "service_header_end" }
      rotation { service_theme&.header_end_rotation }
      pick_strategy { service_theme.present? ? "sequential" : nil }
      time_of_day { nil }
    end

    trait :service_welcome do
      kind { "service_welcome" }
      rotation { service_theme&.welcome_rotation || association(:rotation) }
      pick_strategy { "sequential" }
      time_of_day { nil }
    end

    trait :service_close do
      kind { "service_close" }
      rotation { service_theme&.close_rotation || association(:rotation) }
      pick_strategy { "sequential" }
      time_of_day { nil }
    end
  end
end
