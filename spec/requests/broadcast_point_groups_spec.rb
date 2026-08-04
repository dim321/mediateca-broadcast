# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BroadcastPointGroups', type: :request do
  let(:user) { create(:user, organization: create(:organization, :client)) }
  let(:organization) { user.organization }

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
    it 'allows adding a fleet catalog screen to a client group' do
      sign_in_as(user)
      group = create(:broadcast_point_group, organization: organization)
      screen = create(:screen)

      post add_screens_broadcast_point_group_path(group), params: { screen_ids: [ screen.id ] }

      expect(response).to redirect_to(broadcast_point_group_path(group))
      expect(group.reload.screens).to contain_exactly(screen)
    end

    it 'filters available screens by selected tags on show' do
      sign_in_as(user)
      group = create(:broadcast_point_group, organization: organization)
      retail = create(:tag, name: 'retail')
      lobby = create(:tag, name: 'lobby')
      matching = create(:screen, name: 'Matching screen')
      other = create(:screen, name: 'Other screen')
      create(:screen_tag, screen: matching, tag: retail)
      create(:screen_tag, screen: matching, tag: lobby)
      create(:screen_tag, screen: other, tag: retail)

      get broadcast_point_group_path(group), params: { tag_ids: [ retail.id, lobby.id ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(matching.name)
      expect(response.body).not_to include(other.name)
    end

    it 'rejects adding a screen that would create overlapping media plans' do
      screen = create(:screen)
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
