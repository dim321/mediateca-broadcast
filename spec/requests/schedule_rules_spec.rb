# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ScheduleRules", type: :request do
  let(:user) { create(:user) }
  let(:org) { user.organization }
  let(:playlist) { create(:playlist, organization: org) }
  let(:point_group) { create(:point_group, organization: org) }

  def schedule_params(starts:, ends:)
    {
      schedule_rule: {
        playlist_id: playlist.id,
        starts_at: starts,
        ends_at: ends,
        timezone_context: "organization",
        point_group_ids: [ "", point_group.id.to_s ]
      }
    }
  end

  describe "GET /schedule_rules" do
    it "redirects guests to login" do
      get schedule_rules_path
      expect(response).to redirect_to(login_path)
    end

    it "lists schedules for the organization" do
      sign_in_as(user)
      rule = create(:schedule_rule, organization: org, playlist: playlist, point_group: point_group)
      get schedule_rules_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(playlist.name)
      expect(response.body).to include(point_group.name)
    end
  end

  describe "POST /schedule_rules" do
    before { sign_in_as(user) }

    it "creates a schedule" do
      expect do
        post schedule_rules_path, params: schedule_params(
          starts: "2026-08-01T10:00",
          ends: "2026-08-01T12:00"
        )
      end.to change(ScheduleRule, :count).by(1)
      expect(response).to redirect_to(schedule_rules_path)
    end

    it "rejects overlapping schedules for the same group" do
      create(:schedule_rule,
        organization: org,
        playlist: playlist,
        point_group: point_group,
        starts_at: Time.utc(2026, 8, 1, 9, 0, 0),
        ends_at: Time.utc(2026, 8, 1, 11, 0, 0))

      expect do
        post schedule_rules_path, params: schedule_params(
          starts: "2026-08-01T10:00",
          ends: "2026-08-01T12:00"
        )
      end.not_to change(ScheduleRule, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /schedule_rules/:id" do
    before { sign_in_as(user) }

    it "updates the schedule" do
      rule = create(:schedule_rule, organization: org, playlist: playlist, point_group: point_group)

      patch schedule_rule_path(rule), params: {
        schedule_rule: {
          playlist_id: playlist.id,
          starts_at: "2026-09-01T08:00",
          ends_at: "2026-09-01T10:00",
          timezone_context: "organization",
          point_group_ids: [ "", point_group.id.to_s ]
        }
      }
      expect(response).to redirect_to(schedule_rules_path)
      expect(rule.reload.starts_at).to eq(Time.utc(2026, 9, 1, 8, 0, 0))
    end
  end
end
