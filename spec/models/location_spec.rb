# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: locations
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  operating_hours :jsonb            not null
#  time_zone       :string           default("UTC"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_locations_on_name  (name) UNIQUE
#
RSpec.describe Location, type: :model do
  describe "time_zone" do
    it "requires time_zone" do
      expect(build(:location, time_zone: "")).not_to be_valid
    end

    it "defaults to UTC" do
      expect(described_class.new.time_zone).to eq("UTC")
    end
  end

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

    it "returns open and close bounds for a date" do
      hours = {
        "wed" => [
          { "start" => "09:00", "end" => "13:00" },
          { "start" => "15:00", "end" => "21:00" }
        ]
      }
      bounds = described_class::OperatingHours.day_bounds(hours, Date.new(2026, 9, 2), "Asia/Krasnoyarsk")

      expect(bounds[:open]).to eq(Time.find_zone!("Asia/Krasnoyarsk").local(2026, 9, 2, 9, 0, 0))
      expect(bounds[:close]).to eq(Time.find_zone!("Asia/Krasnoyarsk").local(2026, 9, 2, 21, 0, 0))
    end

    it "returns nil day_bounds when the day is closed" do
      expect(described_class::OperatingHours.day_bounds({}, Date.new(2026, 9, 2), "UTC")).to be_nil
    end

    it "compacts identical weekday windows into a range label" do
      hours = %w[mon tue wed thu fri].index_with do
        [ { "start" => "09:00", "end" => "21:00" } ]
      end

      I18n.with_locale(:ru) do
        expect(described_class::OperatingHours.compact_label(hours)).to eq("пн–пт 09:00–21:00")
      end
    end

    it "returns nil when hours are empty" do
      expect(described_class::OperatingHours.compact_label({})).to be_nil
    end
  end
end
