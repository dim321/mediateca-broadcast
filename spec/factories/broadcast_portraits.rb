# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_portraits
#
#  id                         :bigint           not null, primary key
#  block_frequencies_per_hour :integer          not null, is an Array
#  is_default                 :boolean          default(FALSE), not null
#  kind                       :string           default("cyclic"), not null
#  max_commercial_in_row      :integer          default(3), not null
#  name                       :string           not null
#  neutral_min_seconds        :integer          default(10), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  screen_id                  :bigint
#  service_theme_id           :bigint
#
# Indexes
#
#  index_broadcast_portraits_on_screen_id          (screen_id)
#  index_broadcast_portraits_on_screen_id_unique   (screen_id) UNIQUE WHERE (screen_id IS NOT NULL)
#  index_broadcast_portraits_on_service_theme_id   (service_theme_id)
#  index_broadcast_portraits_one_default_template  (is_default) UNIQUE WHERE ((screen_id IS NULL) AND is_default)
#
# Foreign Keys
#
#  fk_rails_...  (screen_id => screens.id) ON DELETE => cascade
#  fk_rails_...  (service_theme_id => service_themes.id) ON DELETE => restrict
#
FactoryBot.define do
  factory :broadcast_portrait do
    sequence(:name) { |n| "Portrait #{n}" }
    kind { "cyclic" }
    block_frequencies_per_hour { [ 4 ] }
    max_commercial_in_row { 3 }
    neutral_min_seconds { 10 }
    is_default { false }
    screen { nil }

    trait :template do
      screen { nil }
      is_default { false }
    end

    trait :default do
      template
      is_default { true }
    end

    trait :for_screen do
      screen
      is_default { false }
    end
  end
end
