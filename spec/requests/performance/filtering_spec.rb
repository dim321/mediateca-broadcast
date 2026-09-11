# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Performance smoke (queries)", type: :request do
  let(:user) { create(:user, organization: create(:organization, :client)) }
  let(:org) { user.organization }

  before { sign_in_as(user) }

  describe "GET /broadcast_point_groups index" do
    it "keeps queries bounded for a list of screen groups" do
      20.times { |i| create(:broadcast_point_group, organization: org, name: "Group #{i}") }

      _response, count = count_sql_queries do
        get broadcast_point_groups_path
      end

      expect(response).to have_http_status(:success)
      expect(count).to be <= 25
    end
  end

  describe "GET /media_plans index" do
    it "keeps queries bounded for a list of media plans" do
      rotation = create(:rotation, organization: org)
      12.times do |i|
        group = create(:broadcast_point_group, organization: org, name: "Plan group #{i}")
        create(:broadcast_point_group_membership, broadcast_point_group: group, screen: create(:screen))
        create(
          :media_plan,
          organization: org,
          rotation: rotation,
          broadcast_point_group: group,
          starts_at: Time.utc(2026, 8, i + 1, 10, 0, 0),
          ends_at: Time.utc(2026, 8, i + 1, 12, 0, 0)
        )
      end

      _response, count = count_sql_queries do
        get media_plans_path
      end

      expect(response).to have_http_status(:success)
      expect(count).to be <= 30
    end
  end
end
