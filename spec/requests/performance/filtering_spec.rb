# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Performance smoke (queries)", type: :request do
  let(:user) { create(:user) }
  let(:org) { user.organization }

  before { sign_in_as(user) }

  describe "GET /broadcast_points with tag filter" do
    it "не раздувает число SQL при фильтрации по нескольким тегам" do
      tags = Array.new(3) { |i| create(:tag, organization: org, name: "tag#{i}") }
      25.times do |i|
        point = create(:broadcast_point, organization: org, name: "Point #{i}")
        point.tags << tags
      end

      _response, count = count_sql_queries do
        get broadcast_points_path, params: { tag_ids: tags.map(&:id) }
      end

      expect(response).to have_http_status(:success)
      expect(count).to be <= 22
    end
  end

  describe "GET /schedule_rules index" do
    it "держит запросы в разумном пределе при списке расписаний" do
      playlist = create(:playlist, organization: org)
      point_group = create(:point_group, organization: org)
      18.times do |i|
        create(:schedule_rule,
          organization: org,
          playlist: playlist,
          point_group: point_group,
          starts_at: Time.utc(2026, 7, i + 1, 10, 0, 0),
          ends_at: Time.utc(2026, 7, i + 1, 12, 0, 0))
      end

      _response, count = count_sql_queries do
        get schedule_rules_path
      end

      expect(response).to have_http_status(:success)
      expect(count).to be <= 25
    end
  end
end
