# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Avo menu navigation", type: :request do
  let(:user) { create(:user, organization: create(:organization, :operator)) }
  let(:menu_paths) do
    [
      "/avo",
      "/avo/resources/media_assets",
      "/avo/resources/rotations",
      "/avo/resources/locations",
      "/avo/resources/stations",
      "/avo/resources/screens",
      "/avo/resources/tags"
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
