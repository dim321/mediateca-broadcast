# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Avo menu navigation", type: :request do
  let(:user) { create(:user) }
  let(:menu_paths) do
    [
      "/avo",
      "/avo/resources/media_assets",
      "/avo/resources/playlists",
      "/avo/resources/broadcast_points",
      "/avo/resources/schedule_rules"
    ]
  end

  before { sign_in_as(user) }

  it "allows opening each menu section without server errors" do
    menu_paths.each do |path|
      expect { get path }.not_to raise_error
      expect(response).to have_http_status(:ok).or have_http_status(:found)
    end
  end
end
