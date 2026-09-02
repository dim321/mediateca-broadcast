# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin broadcast point group memberships", type: :request do
  include ActiveJob::TestHelper

  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }

  before { sign_in_as(operator) }

  it "enqueues regen from the membership screen after create" do
    group = create(:broadcast_point_group)
    screen = create(:screen)

    expect {
      post admin_broadcast_point_group_memberships_path, params: {
        broadcast_point_group_membership: {
          broadcast_point_group_id: group.id,
          screen_id: screen.id
        }
      }
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)
  end

  it "enqueues regen from the membership screen after destroy" do
    membership = create(:broadcast_point_group_membership)

    expect {
      delete admin_broadcast_point_group_membership_path(membership)
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)
  end
end
