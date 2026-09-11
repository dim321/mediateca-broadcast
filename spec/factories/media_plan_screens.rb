# frozen_string_literal: true

# == Schema Information
#
# Table name: media_plan_screens
#
#  id            :bigint           not null, primary key
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  media_plan_id :bigint           not null
#  screen_id     :bigint           not null
#
# Indexes
#
#  index_media_plan_screens_on_media_plan_id    (media_plan_id)
#  index_media_plan_screens_on_plan_and_screen  (media_plan_id,screen_id) UNIQUE
#  index_media_plan_screens_on_screen_id        (screen_id)
#
# Foreign Keys
#
#  fk_rails_...  (media_plan_id => media_plans.id) ON DELETE => cascade
#  fk_rails_...  (screen_id => screens.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :media_plan_screen do
    media_plan
    screen
  end
end
