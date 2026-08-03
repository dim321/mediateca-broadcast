# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scheduling::MediaPlanConflictDetector do
  let(:client) { create(:organization, :client) }
  let(:operator) { create(:organization, :operator) }
  let(:screen) { create(:screen, organization: operator) }
  let(:rotation) { create(:rotation, organization: client) }
  let(:group) do
    create(:broadcast_point_group, organization: client).tap do |broadcast_point_group|
      create(:broadcast_point_group_membership, broadcast_point_group: broadcast_point_group, screen: screen)
    end
  end

  it 'finds plans whose windows overlap on any shared screen' do
    plan = create(
      :media_plan,
      organization: client,
      rotation: rotation,
      broadcast_point_group: group,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
    )

    conflicts = described_class.call(
      starts_at: Time.utc(2026, 8, 10, 11, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 13, 0, 0),
      screen_ids: [ screen.id ]
    )

    expect(conflicts).to contain_exactly(plan)
  end

  it 'does not treat adjacent windows as conflicts' do
    create(
      :media_plan,
      organization: client,
      rotation: rotation,
      broadcast_point_group: group,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
    )

    conflicts = described_class.call(
      starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 14, 0, 0),
      screen_ids: [ screen.id ]
    )

    expect(conflicts).to be_empty
  end
end
