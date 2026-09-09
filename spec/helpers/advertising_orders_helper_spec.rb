# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdvertisingOrdersHelper, type: :helper do
  describe "#order_screen_meta" do
    it "returns the location without the station" do
      location = create(:location, name: "ТЦ Галерея")
      station = create(:station, location: location, name: "Станция Невидимая")
      screen = create(:screen, station: station, name: "Витрина 7")

      expect(helper.order_screen_meta(screen)).to eq("ТЦ Галерея")
    end
  end

  describe "#order_grid_date_value" do
    it "formats dates as dd.mm.yyyy" do
      expect(helper.order_grid_date_value(Date.new(2026, 6, 3))).to eq("03.06.2026")
    end
  end
end
