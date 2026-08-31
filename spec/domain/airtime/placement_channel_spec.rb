# frozen_string_literal: true

require "rails_helper"

RSpec.describe Airtime::PlacementChannel do
  let(:owner) { create(:organization, :client) }
  let(:placer) { create(:organization, :client) }
  let(:screen) { create(:screen, owner_organization: owner) }
  let(:owner_group) do
    create(:broadcast_point_group, organization: owner).tap do |g|
      create(:broadcast_point_group_membership, broadcast_point_group: g, screen: screen)
    end
  end
  let(:placer_group) do
    create(:broadcast_point_group, organization: placer).tap do |g|
      create(:broadcast_point_group_membership, broadcast_point_group: g, screen: screen)
    end
  end

  it "allows commercial on the owner homogeneous group (AE4 allow)" do
    expect do
      described_class.assert!(
        organization: placer,
        broadcast_point_group: owner_group,
        placement_kind: :commercial
      )
    end.not_to raise_error
  end

  it "rejects commercial on placer-assembled group of owned screens (AE4 reject)" do
    expect do
      described_class.assert!(
        organization: placer,
        broadcast_point_group: placer_group,
        placement_kind: :commercial
      )
    end.to raise_error(ArgumentError, /owner organization group/)
  end

  it "rejects foreign own_atmosphere on owner group" do
    expect do
      described_class.assert!(
        organization: placer,
        broadcast_point_group: owner_group,
        placement_kind: :own_atmosphere
      )
    end.to raise_error(ArgumentError, /own\/atmosphere/)
  end
end
