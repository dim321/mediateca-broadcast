# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Internal playlist reorder", type: :request do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, organization: user.organization) }
  let!(:item_one) { create(:playlist_item, playlist: playlist, position: 1) }
  let!(:item_two) { create(:playlist_item, playlist: playlist, position: 2) }

  describe "PATCH /internal/playlists/:playlist_id/reorder" do
    it "returns 401 when not signed in" do
      patch internal_playlist_reorder_path(playlist_id: playlist.id),
        params: { playlist_item_ids: [ item_two.id, item_one.id ] },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "reorders items when ids match the playlist" do
      sign_in_as(user)
      patch internal_playlist_reorder_path(playlist_id: playlist.id),
        params: { playlist_item_ids: [ item_two.id, item_one.id ] },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:no_content)
      expect(item_one.reload.position).to eq(2)
      expect(item_two.reload.position).to eq(1)
    end

    it "returns 422 when ids do not match" do
      sign_in_as(user)
      patch internal_playlist_reorder_path(playlist_id: playlist.id),
        params: { playlist_item_ids: [ item_one.id ] },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 404 for another organization playlist" do
      other = create(:playlist)
      sign_in_as(user)
      patch internal_playlist_reorder_path(playlist_id: other.id),
        params: { playlist_item_ids: [] },
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
