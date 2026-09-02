# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_portraits
#
#  id                       :bigint           not null, primary key
#  block_frequency_per_hour :integer          not null
#  is_default               :boolean          default(FALSE), not null
#  kind                     :string           default("cyclic"), not null
#  max_commercial_in_row    :integer          default(3), not null
#  name                     :string           not null
#  neutral_min_seconds      :integer          default(10), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  station_id               :bigint
#
# Indexes
#
#  index_broadcast_portraits_on_station_id_unique  (station_id) UNIQUE WHERE (station_id IS NOT NULL)
#  index_broadcast_portraits_one_default_template  (is_default) UNIQUE WHERE ((station_id IS NULL) AND is_default)
#
# Foreign Keys
#
#  fk_rails_...  (station_id => stations.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :broadcast_portrait do
    sequence(:name) { |n| "Portrait #{n}" }
    kind { "cyclic" }
    block_frequency_per_hour { 4 }
    max_commercial_in_row { 3 }
    neutral_min_seconds { 10 }
    is_default { false }
    station { nil }

    trait :template do
      station { nil }
      is_default { false }
    end

    trait :default do
      template
      is_default { true }
    end

    trait :for_station do
      station
      is_default { false }
    end
  end
end
