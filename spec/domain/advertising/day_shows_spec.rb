# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::DayShows do
  let(:date) { Date.new(2026, 6, 6) } # суббота

  def shows(strategy, screen_index: 0, screen_count: 2, hours: 3, rate: 3)
    described_class.call(
      date: date,
      shows_per_hour: rate,
      hours: hours,
      distribution_strategy: strategy,
      screen_index: screen_index,
      screen_count: screen_count
    )
  end

  it "возвращает частоту на число часов для linear" do
    expect(shows("linear")).to eq(9)
  end

  it "обнуляет выходные для weekdays и будни для weekends" do
    expect(shows("weekdays")).to eq(0)
    expect(shows("weekends")).to eq(9)
    expect(described_class.call(
      date: Date.new(2026, 6, 5),
      shows_per_hour: 3,
      hours: 3,
      distribution_strategy: "weekdays",
      screen_index: 0,
      screen_count: 1
    )).to eq(9)
  end

  it "делит чётные и нечётные дни месяца" do
    expect(shows("even_days")).to eq(9)
    expect(shows("odd_days")).to eq(0)
  end

  it "расставляет шахматку по половине экранов" do
    expect(shows("chess", screen_index: 0, screen_count: 2)).to eq(0)
    expect(shows("chess", screen_index: 1, screen_count: 2)).to eq(9)
  end
end
