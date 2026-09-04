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
#
# Indexes
#
#  index_broadcast_portrait_blocks_on_broadcast_portrait_id  (broadcast_portrait_id)
#  index_broadcast_portrait_blocks_on_portrait_and_position  (broadcast_portrait_id,position) UNIQUE
#  index_broadcast_portrait_blocks_on_rotation_id            (rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_portrait_id => broadcast_portraits.id) ON DELETE => cascade
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
FactoryBot.define do
  factory :broadcast_portrait_block do
    broadcast_portrait
    sequence(:position) { |n| n }
    kind { "commercial" }

    trait :commercial do
      kind { "commercial" }
      rotation { nil }
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
      rotation { nil }
      pick_strategy { nil }
      time_of_day { nil }
    end

    trait :service_header_end do
      kind { "service_header_end" }
      rotation { nil }
      pick_strategy { nil }
      time_of_day { nil }
    end

    trait :service_welcome do
      kind { "service_welcome" }
      rotation
      pick_strategy { "sequential" }
      time_of_day { nil }
    end

    trait :service_close do
      kind { "service_close" }
      rotation
      pick_strategy { "sequential" }
      time_of_day { nil }
    end
  end
end
