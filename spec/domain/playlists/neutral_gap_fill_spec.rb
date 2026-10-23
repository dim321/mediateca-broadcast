# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::NeutralGapFill do
  def clip(name, duration, position)
    { media_asset: name, duration_seconds: duration, position: position }
  end

  it "places the longest clip that fits, then the next longest that fits the remainder" do
    placed = described_class.call(
      clips: [ clip(:medium, 25, 0), clip(:long, 30, 1) ],
      window_seconds: 60
    )

    expect(placed.map { |pick| pick[:duration_seconds] }).to eq([ 30, 25 ])
    expect(placed.map { |pick| pick[:media_asset] }).to eq([ :long, :medium ])
  end

  it "skips a longer clip that does not fit the remainder and takes the next one that does" do
    placed = described_class.call(
      clips: [ clip(:mid, 20, 0), clip(:long, 30, 1), clip(:short, 15, 2) ],
      window_seconds: 45
    )

    expect(placed.map { |pick| pick[:duration_seconds] }).to eq([ 30, 15 ])
  end

  it "repeats the catalog until no eligible clip fits the remainder" do
    placed = described_class.call(
      clips: [ clip(:only, 10, 0) ],
      window_seconds: 25
    )

    expect(placed.map { |pick| pick[:duration_seconds] }).to eq([ 10, 10 ])
  end

  it "leaves the window empty when every clip is longer than it" do
    placed = described_class.call(
      clips: [ clip(:long, 30, 0) ],
      window_seconds: 20
    )

    expect(placed).to eq([])
  end
end
