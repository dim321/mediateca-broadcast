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
    it 'allows adding an operator-owned catalog screen to a client group' do
      sign_in_as(user)
      group = create(:broadcast_point_group, organization: organization)
      screen = create(:screen, organization: create(:organization, :operator))

      post add_screens_broadcast_point_group_path(group), params: { screen_ids: [ screen.id ] }

      expect(response).to redirect_to(broadcast_point_group_path(group))
      expect(group.reload.screens).to contain_exactly(screen)
    end
  end
end
