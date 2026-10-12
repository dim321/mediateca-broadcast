# frozen_string_literal: true

# == Schema Information
#
# Table name: agent_commands
#
#  id           :bigint           not null, primary key
#  command_type :string           not null
#  finished_at  :datetime
#  issued_at    :datetime         not null
#  params       :jsonb            not null
#  result_error :string
#  status       :string           default("pending"), not null
#  succeeded    :boolean
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  public_id    :string           not null
#  screen_id    :bigint           not null
#  station_id   :bigint           not null
#
# Indexes
#
#  index_agent_commands_on_public_id              (public_id) UNIQUE
#  index_agent_commands_on_screen_id              (screen_id)
#  index_agent_commands_on_station_id             (station_id)
#  index_agent_commands_on_station_id_and_status  (station_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (screen_id => screens.id)
#  fk_rails_...  (station_id => stations.id)
#
FactoryBot.define do
  factory :agent_command do
    station
    screen { association :screen, station: station }
    sequence(:public_id) { |n| "cmd_factory_#{n}" }
    command_type { "restart_stream" }
    params { {} }
    issued_at { Time.utc(2026, 10, 9, 11, 1, 0) }
    status { "pending" }
  end
end
