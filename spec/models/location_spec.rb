# frozen_string_literal: true

require "rails_helper"

RSpec.describe Location, type: :model do
  describe "operating hours" do
    it "round-trips weekly windows" do
      location = create(
        :location,
        operating_hours: { "mon" => [ { "start" => "09:00", "end" => "18:00" } ] }
      )

      expect(location.reload.operating_hours_configured?).to be(true)
      expect(location.operating_hours["mon"].first["start"]).to eq("09:00")
    end

    it "counts open minutes inside a clock hour" do
      location = build(
        :location,
        operating_hours: { "mon" => [ { "start" => "09:00", "end" => "18:00" } ] }
      )
      # 2026-08-10 is Monday
      noon = Time.utc(2026, 8, 10, 12, 0, 0)

      expect(location.operating_minutes_in_hour(noon)).to eq(60)
    end

    it "rejects invalid day keys that bypass the writer" do
      location = build(:location)
      location.write_attribute(:operating_hours, { "monday" => [ { "start" => "09:00", "end" => "10:00" } ] })

      expect(location).not_to be_valid
    end

    it "strips blank day windows, unknown days, and HH:MM:SS clocks on assign" do
      location = build(
        :location,
        operating_hours: {
          "mon" => [ { "start" => "09:00:00", "end" => "18:00:00" } ],
          "tue" => [ { "start" => "", "end" => "" } ],
          "monday" => [ { "start" => "09:00", "end" => "10:00" } ]
        }
      )

      expect(location.operating_hours).to eq(
        "mon" => [ { "start" => "09:00", "end" => "18:00" } ]
      )
    end
  end
end
