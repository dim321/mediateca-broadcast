# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PointGroups", type: :request do
  let(:user) { create(:user) }
  let(:org) { user.organization }

  describe "POST /point_groups" do
    it "requires sign-in" do
      post point_groups_path, params: { point_group: { name: "G1" } }
      expect(response).to redirect_to(login_path)
    end

    it "creates a group in the user organization" do
      sign_in_as(user)
      expect do
        post point_groups_path, params: { point_group: { name: "Supermarket A" } }
      end.to change(PointGroup, :count).by(1)
      expect(response).to redirect_to(point_group_path(PointGroup.last))
      expect(PointGroup.last.organization_id).to eq(org.id)
    end
  end

  describe "POST /point_groups/:id/add_points" do
    let(:group) { create(:point_group, organization: org) }
    let(:point) { create(:broadcast_point, organization: org) }

    it "adds selected points to the group" do
      sign_in_as(user)
      post add_points_point_group_path(group), params: { broadcast_point_ids: [ point.id ] }
      expect(response).to redirect_to(point_group_path(group))
      expect(group.reload.broadcast_points).to contain_exactly(point)
    end

    it "returns not found for another organization's group" do
      sign_in_as(user)
      other_group = create(:point_group)
      post add_points_point_group_path(other_group), params: { broadcast_point_ids: [ point.id ] }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /point_groups/:id/remove_member" do
    let(:group) { create(:point_group, organization: org) }
    let(:point) { create(:broadcast_point, organization: org) }

    before do
      create(:point_group_membership, point_group: group, broadcast_point: point)
    end

    it "removes a point from the group" do
      sign_in_as(user)
      delete remove_member_point_group_path(group), params: { broadcast_point_id: point.id }
      expect(response).to redirect_to(point_group_path(group))
      expect(group.reload.broadcast_points).to be_empty
    end
  end
end
