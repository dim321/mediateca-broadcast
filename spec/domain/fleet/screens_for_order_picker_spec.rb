# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fleet::ScreensForOrderPicker do
  it "returns every screen, including operator fleet and other organizations" do
    fleet = create(:screen, name: "Fleet")
    client_screen = create(:screen, :owned, name: "Owned")
    other_screen = create(:screen, :owned, name: "Other")
    create(:screen_tag, screen: fleet, tag: create(:tag, name: "lobby"))
    create(:broadcast_portrait, :for_screen, screen: fleet, name: "Цикл")

    result = described_class.call

    expect(result).to include(fleet, client_screen, other_screen)
    loaded = result.find { |screen| screen.id == fleet.id }
    expect(loaded.association(:station).loaded?).to be(true)
    expect(loaded.station.association(:location).loaded?).to be(true)
    expect(loaded.association(:tags).loaded?).to be(true)
    expect(loaded.association(:broadcast_portrait).loaded?).to be(true)
  end
end
