# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agent::PackageBuilder do
  describe '.call' do
    it 'includes plans intersecting the station offline-cache horizon' do
      client = create(:organization, :client)
      operator = create(:organization, :operator)
      station = create(:station, organization: operator, offline_cache_hours: 24)
      screen = create(:screen, organization: operator, station:)
      plan = create_plan(client:, screen:, starts_at: 12.hours.from_now, ends_at: 36.hours.from_now)

      package = described_class.call(station:, now: Time.current)

      expect(package[:items]).to contain_exactly(
        include(media_plan_id: plan.id, screen_ids: [ screen.id ])
      )
      expect(package[:screen_map]).to eq(screen.id.to_s => [ plan.id ])
    end
  end

  private

  def create_plan(client:, screen:, starts_at:, ends_at:)
    rotation = create(:rotation, organization: client)
    media_asset = create(:media_asset, :ready, :with_png_file, organization: client)
    create(:rotation_item, rotation:, media_asset:, position: 1)
    group = create(:broadcast_point_group, organization: client)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen:)
    create(:media_plan, organization: client, rotation:, broadcast_point_group: group, starts_at:, ends_at:)
  end
end
