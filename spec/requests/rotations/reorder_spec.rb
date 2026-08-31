# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Internal rotation reorder", type: :request do
  let(:user) { create(:user) }
  let(:rotation) { create(:rotation, organization: user.organization) }
  let!(:item_one) { create(:rotation_item, rotation: rotation, position: 1) }
  let!(:item_two) { create(:rotation_item, rotation: rotation, position: 2) }

  describe "PATCH /internal/rotations/:rotation_id/reorder" do
    it "returns 401 when not signed in" do
      patch internal_rotation_reorder_path(rotation_id: rotation.id),
        params: { rotation_item_ids: [ item_two.id, item_one.id ] },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "reorders items when ids match the rotation" do
      sign_in_as(user)
      patch internal_rotation_reorder_path(rotation_id: rotation.id),
        params: { rotation_item_ids: [ item_two.id, item_one.id ] },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:no_content)
      expect(item_one.reload.position).to eq(2)
      expect(item_two.reload.position).to eq(1)
    end

    it "returns 422 when ids do not match" do
      sign_in_as(user)
      patch internal_rotation_reorder_path(rotation_id: rotation.id),
        params: { rotation_item_ids: [ item_one.id ] },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 404 for another organization rotation" do
      other = create(:rotation)
      sign_in_as(user)
      patch internal_rotation_reorder_path(rotation_id: other.id),
        params: { rotation_item_ids: [] },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
