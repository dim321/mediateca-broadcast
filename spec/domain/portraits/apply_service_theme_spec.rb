# frozen_string_literal: true

require "rails_helper"

RSpec.describe Portraits::ApplyServiceTheme do
  include ActiveJob::TestHelper

  let(:theme) { create(:service_theme) }
  let(:screen) { create(:screen) }
  let(:portrait) { create(:broadcast_portrait, :for_screen, screen: screen) }

  it "upserts four service blocks and filler with pick strategies, keeping other blocks (AE3)" do
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: portrait, position: 1)

    described_class.call(
      portrait: portrait,
      theme: theme,
      pick_strategies: { header_start: "random", welcome: "ordered" }
    )

    portrait.reload
    expect(portrait.service_theme).to eq(theme)
    expect(portrait.blocks.order(:position).map(&:kind)).to include(
      "commercial", "filler", "service_header_start", "service_header_end", "service_welcome", "service_close"
    )
    expect(portrait.blocks.find_by!(kind: "service_header_start")).to have_attributes(
      service_theme: theme,
      rotation: theme.header_start_rotation,
      pick_strategy: "random"
    )
    expect(portrait.blocks.find_by!(kind: "service_welcome")).to have_attributes(
      service_theme: theme,
      rotation: theme.welcome_rotation,
      pick_strategy: "ordered"
    )
    expect(portrait.blocks.find_by!(kind: "commercial")).to be_present
  end

  it "upserts filler from theme neutral rotation and clears theme-owned filler" do
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: portrait, position: 1)

    described_class.call(
      portrait: portrait,
      theme: theme,
      pick_strategies: { neutral: "random" }
    )

    portrait.reload
    filler = portrait.blocks.find_by!(kind: "filler")
    expect(filler).to have_attributes(
      service_theme: theme,
      rotation: theme.neutral_rotation,
      pick_strategy: "random"
    )

    described_class.call(portrait: portrait, theme: nil)
    portrait.reload
    expect(portrait.blocks.map(&:kind)).to eq(%w[commercial])
  end

  it "upserts a theme-owned filler over an existing non-theme filler" do
    other_rotation = create(:rotation, organization: theme.organization)
    create(:broadcast_portrait_block, :filler, broadcast_portrait: portrait, position: 1,
      rotation: other_rotation, pick_strategy: "sequential")

    described_class.call(portrait: portrait, theme: theme)

    expect(portrait.reload.blocks.find_by!(kind: "filler")).to have_attributes(
      service_theme: theme,
      rotation: theme.neutral_rotation,
      pick_strategy: "sequential"
    )
  end

  it "keeps a non-theme filler when clearing a theme that never owned filler" do
    other_rotation = create(:rotation, organization: theme.organization)
    create(:broadcast_portrait_block, :filler, broadcast_portrait: portrait, position: 1,
      rotation: other_rotation, pick_strategy: "sequential")

    described_class.call(portrait: portrait, theme: nil)

    expect(portrait.reload.blocks.find_by!(kind: "filler").rotation).to eq(other_rotation)
  end

  it "applies different themes to screens of the same station (AE14)" do
    station = screen.station
    other_screen = create(:screen, station: station)
    other_portrait = create(:broadcast_portrait, :for_screen, screen: other_screen)
    other_theme = create(:service_theme, organization: theme.organization)

    described_class.call(portrait: portrait, theme: theme)
    described_class.call(portrait: other_portrait, theme: other_theme)

    expect(portrait.reload.service_theme).to eq(theme)
    expect(other_portrait.reload.service_theme).to eq(other_theme)
    expect(portrait.blocks.find_by!(kind: "service_welcome").rotation).to eq(theme.welcome_rotation)
    expect(other_portrait.blocks.find_by!(kind: "service_welcome").rotation).to eq(other_theme.welcome_rotation)
  end

  it "clears theme blocks when theme is nil" do
    create(:broadcast_portrait_block, :commercial, broadcast_portrait: portrait, position: 1)
    described_class.call(portrait: portrait, theme: theme)

    described_class.call(portrait: portrait, theme: nil)

    portrait.reload
    expect(portrait.service_theme).to be_nil
    expect(portrait.blocks.map(&:kind)).to eq(%w[commercial])
  end
end
