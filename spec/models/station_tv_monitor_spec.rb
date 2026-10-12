# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: station_tv_monitors
#
#  id                            :bigint           not null, primary key
#  auto_restart_when_not_playing :boolean          default(TRUE), not null
#  health_interval_seconds       :integer          default(30), not null
#  telemetry_interval_seconds    :integer          default(60), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  station_id                    :bigint           not null
#
# Indexes
#
#  index_station_tv_monitors_on_station_id  (station_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (station_id => stations.id)
#
RSpec.describe StationTvMonitor do
  it "rejects a health interval below the station clamp" do
    monitor = build(:station_tv_monitor, health_interval_seconds: 4)

    expect(monitor).not_to be_valid
    expect(monitor.errors[:health_interval_seconds]).to be_present
  end

  it "stores an explicit false auto-restart flag" do
    monitor = create(:station_tv_monitor, auto_restart_when_not_playing: false)

    expect(monitor.reload.auto_restart_when_not_playing).to be(false)
  end
end
