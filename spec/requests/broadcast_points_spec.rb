# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BroadcastPoints", type: :request do
  let(:user) { create(:user) }
  let(:org) { user.organization }

  describe "GET /broadcast_points" do
    it "redirects guests to login" do
      get broadcast_points_path
      expect(response).to redirect_to(login_path)
    end

    it "lists points for the organization" do
      sign_in_as(user)
      create(:broadcast_point, organization: org, name: "Alpha")
      get broadcast_points_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Alpha")
    end

    it "filters by tag_ids using AND semantics" do
      sign_in_as(user)
      tag_a = create(:tag, organization: org, name: "a")
      tag_b = create(:tag, organization: org, name: "b")
      both = create(:broadcast_point, organization: org, name: "Both")
      only_a = create(:broadcast_point, organization: org, name: "OnlyA")
      both.tags << tag_a
      both.tags << tag_b
      only_a.tags << tag_a

      get broadcast_points_path, params: { tag_ids: [ tag_a.id, tag_b.id ] }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Both")
      expect(response.body).not_to include("OnlyA")
    end
  end

  describe "POST /broadcast_points" do
    before { sign_in_as(user) }

    it "creates a point and new tags from comma-separated names" do
      expect do
        post broadcast_points_path, params: {
          broadcast_point: {
            name: "Store 1",
            city: "Krasnoyarsk",
            new_tag_names: "retail, flagship",
            tag_ids: [ "" ]
          }
        }
      end.to change(BroadcastPoint, :count).by(1)
        .and change(Tag, :count).by(2)
      expect(response).to redirect_to(broadcast_points_path)
      point = BroadcastPoint.find_by!(name: "Store 1")
      expect(point.tags.map(&:name)).to contain_exactly("retail", "flagship")
    end
  end
end
