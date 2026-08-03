# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BroadcastPointGroups', type: :request do
  let(:user) { create(:user, organization: create(:organization, :client)) }
  let(:organization) { user.organization }
  let(:operator) { create(:organization, :operator) }

  describe 'POST /broadcast_point_groups' do
    it 'creates a screen group in the client organization' do
      sign_in_as(user)

      expect do
        post broadcast_point_groups_path, params: { broadcast_point_group: { name: 'Mall screens' } }
      end.to change(BroadcastPointGroup, :count).by(1)

      expect(response).to redirect_to(broadcast_point_group_path(BroadcastPointGroup.last))
      expect(BroadcastPointGroup.last.organization).to eq(organization)
    end
  end

  describe 'POST /broadcast_point_groups/:id/add_screens' do
    it 'allows adding an operator-owned catalog screen to a client group' do
      sign_in_as(user)
      group = create(:broadcast_point_group, organization: organization)
      screen = create(:screen, organization: operator)

      post add_screens_broadcast_point_group_path(group), params: { screen_ids: [ screen.id ] }

      expect(response).to redirect_to(broadcast_point_group_path(group))
      expect(group.reload.screens).to contain_exactly(screen)
    end

    it 'rejects screens that are not in the operator catalog' do
      sign_in_as(user)
      group = create(:broadcast_point_group, organization: organization)
      client_screen = create(:screen, organization: create(:organization, :client))

      post add_screens_broadcast_point_group_path(group), params: { screen_ids: [ client_screen.id ] }

      expect(response).to redirect_to(broadcast_point_group_path(group))
      expect(flash[:alert]).to be_present
      expect(group.reload.screens).to be_empty
    end

    it 'rejects adding a screen that would create overlapping media plans' do
      screen = create(:screen, organization: operator)
      other_group = create(:broadcast_point_group, organization: organization)
      create(:broadcast_point_group_membership, broadcast_point_group: other_group, screen:)
      create(
        :media_plan,
        organization:,
        broadcast_point_group: other_group,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
      )

      target_group = create(:broadcast_point_group, organization: organization)
      create(
        :media_plan,
        organization:,
        broadcast_point_group: target_group,
        starts_at: Time.utc(2026, 8, 10, 11, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 13, 0, 0)
      )

      membership = target_group.broadcast_point_group_memberships.new(screen:)

      expect(membership).not_to be_valid
      expect(membership.errors[:screen]).to include('overlaps an existing media plan for this screen')
    end
  end
end
