# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::PrintMonthBlocks do
  def blocks_for(dates)
    described_class.new(placement_dates: dates).call
  end

  it "returns one block for a 20-day span across two months (AE9)" do
    dates = (Date.new(2026, 12, 15)..Date.new(2027, 1, 3)).to_a

    result = blocks_for(dates)

    expect(result.size).to eq(1)
    expect(result.first.dates).to eq(dates)
    expect(result.first.label).to include("2026")
    expect(result.first.label).to include("2027")
  end

  it "returns two month blocks for a span longer than 31 days (AE9)" do
    dates = (Date.new(2026, 12, 25)..Date.new(2027, 1, 31)).to_a

    result = blocks_for(dates)

    expect(result.size).to eq(2)
    expect(result.first.dates).to eq((Date.new(2026, 12, 25)..Date.new(2026, 12, 31)).to_a)
    expect(result.second.dates).to eq((Date.new(2027, 1, 1)..Date.new(2027, 1, 31)).to_a)
  end

  it "returns three month blocks when the span crosses three months" do
    dates = (Date.new(2026, 11, 25)..Date.new(2027, 1, 5)).to_a

    result = blocks_for(dates)

    expect(result.size).to eq(3)
  end

  it "starts the first long-span block from the first placement date in the month" do
    dates = [ Date.new(2026, 12, 25), Date.new(2026, 12, 28), Date.new(2027, 1, 2) ]

    result = blocks_for(dates)

    expect(result.first.dates.first).to eq(Date.new(2026, 12, 25))
  end
end
