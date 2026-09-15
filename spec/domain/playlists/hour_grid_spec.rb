# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::HourGrid do
  let(:portrait) { build(:broadcast_portrait, block_frequencies_per_hour: [ 4, 6, 12 ]) }

  def plan(shows, kind: :commercial)
    instance_double(MediaPlan, commercial?: kind == :commercial, shows_per_hour: shows)
  end

  it "uses LCM of catalog commercial frequencies" do
    expect(described_class.slot_count(portrait: portrait, occupying_plans: [ plan(4), plan(6) ])).to eq(12)
  end

  it "falls back to max portrait frequency when no catalog commercials occupy" do
    expect(described_class.slot_count(portrait: portrait, occupying_plans: [ plan(nil, kind: :own_atmosphere) ])).to eq(12)
    expect(described_class.slot_count(portrait: portrait, occupying_plans: [ plan(7) ])).to eq(12)
  end

  it "places 4 and 6 hits on a 12-slot hour" do
    four = plan(4)
    six = plan(6)
    hits_four = (0...12).select { |i| described_class.catalog_hit?(four, i, 12) }
    hits_six = (0...12).select { |i| described_class.catalog_hit?(six, i, 12) }

    expect(hits_four).to eq([ 0, 3, 6, 9 ])
    expect(hits_six).to eq([ 0, 2, 4, 6, 8, 10 ])
  end
end
