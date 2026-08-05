# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Fleet::Screens', type: :request do
  let(:org_a) { create(:organization, :client) }
  let(:org_b) { create(:organization, :client) }
  let(:manager_a) { create(:user, :manager, organization: org_a) }
  let(:station) { create(:station) }
  let(:screen) { create(:screen, station: station) }

  it 'shows only the current org air block on a shared screen (AE6)' do
    plan_a = create_plan(org: org_a, screen: screen, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    plan_b = create_plan(org: org_b, screen: screen, starts_at: 30.minutes.ago, ends_at: 90.minutes.from_now)

    sign_in_as(manager_a)
    get fleet_screen_path(screen)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(plan_a.rotation.name)
    expect(response.body).not_to include(plan_b.rotation.name)
  end

  it 'does not call the agent package builder from LK' do
    source = File.read(Rails.root.join('app/controllers/fleet/screens_controller.rb'))
    expect(source).not_to include('Agent::PackageBuilder')
  end

  def create_plan(org:, screen:, starts_at:, ends_at:)
    rotation = create(:rotation, organization: org, name: "Rotation #{org.id}-#{SecureRandom.hex(2)}")
    asset = create(:media_asset, :ready, :with_png_file, organization: org)
    create(:rotation_item, rotation: rotation, media_asset: asset)
    group = create(:broadcast_point_group, organization: org)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    create(
      :media_plan,
      organization: org,
      rotation: rotation,
      broadcast_point_group: group,
      starts_at: starts_at,
      ends_at: ends_at
    )
  end
end
