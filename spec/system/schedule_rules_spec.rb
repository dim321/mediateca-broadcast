# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Schedule rules UI", type: :system do
  let(:user) { create(:user) }
  let(:org) { user.organization }
  let(:playlist) { create(:playlist, organization: org, name: "Morning mix") }
  let(:point_group) { create(:point_group, organization: org, name: "Lobby screens") }

  before do
    playlist
    point_group
    visit login_path
    fill_in I18n.t("sessions.new.email"), with: user.email
    fill_in I18n.t("sessions.new.password"), with: "password123456"
    click_button I18n.t("sessions.new.submit")
  end

  it "creates a schedule and blocks overlapping ranges" do
    visit new_schedule_rule_path
    select playlist.name, from: "schedule_rule_playlist_id"
    fill_in "schedule_rule_starts_at", with: "2026-10-01T10:00"
    fill_in "schedule_rule_ends_at", with: "2026-10-01T12:00"
    check "schedule_rule_point_group_#{point_group.id}"
    find("form[action*='schedule_rules'] input[type='submit']").click

    expect(page).to have_current_path(schedule_rules_path, ignore_query: true)
    expect(page).to have_content(playlist.name)

    visit new_schedule_rule_path
    select playlist.name, from: "schedule_rule_playlist_id"
    fill_in "schedule_rule_starts_at", with: "2026-10-01T11:00"
    fill_in "schedule_rule_ends_at", with: "2026-10-01T13:00"
    check "schedule_rule_point_group_#{point_group.id}"
    find("form[action*='schedule_rules'] input[type='submit']").click

    expect(page).to have_content(I18n.t("activerecord.errors.models.schedule_rule.attributes.base.overlaps_existing"))
  end
end
