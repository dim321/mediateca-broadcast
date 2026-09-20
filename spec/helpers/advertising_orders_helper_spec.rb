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

  describe "#order_screen_picker_filter_suggestions" do
    it "collects unique location names, tag names and frequency values from picker screens" do
      gallery = create(:location, name: "ТЦ Галерея")
      atrium = create(:location, name: "Атриум")
      first = create(:screen, station: create(:station, location: gallery))
      second = create(:screen, station: create(:station, location: atrium))
      showcase = create(:tag, name: "витрина")
      hall = create(:tag, name: "холл")
      create(:screen_tag, screen: first, tag: showcase)
      create(:screen_tag, screen: first, tag: hall)
      create(:screen_tag, screen: second, tag: hall)
      create(:broadcast_portrait, :for_screen, screen: first, block_frequencies_per_hour: [ 1, 4, 6 ])
      create(:broadcast_portrait, :for_screen, screen: second, block_frequencies_per_hour: [ 4, 12 ])

      expect(helper.order_screen_picker_filter_suggestions([ first, second ])).to eq(
        locations: [ "Атриум", "ТЦ Галерея" ],
        tags: [ "витрина", "холл" ],
        frequencies: [ 1, 4, 6, 12 ]
      )
    end
  end

  describe "#order_screen_frequencies_label" do
    it "joins portrait block frequencies for the screen picker" do
      screen = create(:screen)
      create(:broadcast_portrait, :for_screen, screen: screen, block_frequencies_per_hour: [ 1, 3, 6 ])

      expect(helper.order_screen_frequencies_label(screen)).to eq("1, 3, 6")
    end

    it "returns blank when the screen has no portrait" do
      expect(helper.order_screen_frequencies_label(create(:screen))).to be_blank
    end
  end

  describe "#order_grid_date_value" do
    it "formats dates as dd.mm.yyyy" do
      expect(helper.order_grid_date_value(Date.new(2026, 6, 3))).to eq("03.06.2026")
    end
  end

  describe "#advertising_grid_months" do
    it "groups dates in chronological month blocks" do
      dates = (Date.new(2026, 8, 30)..Date.new(2026, 9, 2)).to_a

      expect(helper.advertising_grid_months(dates)).to eq(
        Date.new(2026, 8, 1) => dates.first(2),
        Date.new(2026, 9, 1) => dates.last(2)
      )
    end
  end

  describe "#advertising_grid_month_label" do
    it "uses nominative Russian month names with a capital letter" do
      I18n.with_locale(:ru) do
        expect(helper.advertising_grid_month_label(Date.new(2026, 9, 1))).to eq("Сентябрь 2026")
      end
    end
  end

  describe "#order_grid_date_field_tag" do
    it "keeps a dd.mm.yyyy text field and offers a nameless native date picker" do
      html = Nokogiri::HTML.fragment(
        helper.order_grid_date_field_tag(:grid_from, Date.new(2026, 6, 3), html_class: "input")
      )
      display = html.at_css("input[name='grid_from']")
      picker = html.at_css("input[type='date']")

      expect(html.at_css("[data-controller='order-grid-date']")).to be_present
      expect(display["type"]).to eq("text")
      expect(display["value"]).to eq("03.06.2026")
      expect(picker["name"]).to be_blank
      expect(picker["value"]).to eq("2026-06-03")
    end
  end

  describe "#order_screen_hours_json" do
    it "lists open clock hours independent of the default 09:00–12:00 window" do
      location = create(:location, operating_hours: AdvertisingNetwork::WEEKLY_HOURS, time_zone: "UTC")
      screen = create(:screen, station: create(:station, location: location))
      helper.instance_variable_set(:@grid_dates, [ Date.new(2026, 6, 3) ])
      helper.instance_variable_set(:@advertising_order, AdvertisingOrder.new)

      expect(helper.order_screen_hours_json(screen)).to eq("2026-06-03" => (9..20).to_a)
    end
  end
end
