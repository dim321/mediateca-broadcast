# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin rotation items", type: :request do
  include ActiveJob::TestHelper

  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }

  before { sign_in_as(operator) }

  it "enqueues regen from the rotation after create" do
    rotation = create(:rotation)
    asset = create(:media_asset, :ready, :with_png_file, organization: rotation.organization)
    station = create(:station)
    portrait = create(:broadcast_portrait, :for_screen, screen: create(:screen, station: station))
    create(:broadcast_portrait_block, :filler, broadcast_portrait: portrait, rotation: rotation)

    expect {
      post admin_rotation_items_path, params: {
        rotation_item: {
          rotation_id: rotation.id,
          media_asset_id: asset.id,
          position: 1
        }
      }
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)
  end

  it "enqueues regen from the rotation after destroy" do
    rotation = create(:rotation)
    item = create(:rotation_item, rotation: rotation)
    station = create(:station)
    portrait = create(:broadcast_portrait, :for_screen, screen: create(:screen, station: station))
    create(:broadcast_portrait_block, :filler, broadcast_portrait: portrait, rotation: rotation)

    expect {
      delete admin_rotation_item_path(item)
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)
  end
end
