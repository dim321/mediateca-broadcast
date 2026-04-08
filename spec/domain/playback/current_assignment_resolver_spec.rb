# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playback::CurrentAssignmentResolver do
  describe ".call" do
    def build_active_assignment_scenario
      organization = create(:organization, time_zone: "Europe/Moscow")
      broadcast_point = create(:broadcast_point, organization:, time_zone: nil)
      point_group = create(:point_group, organization:)
      create(:point_group_membership, point_group:, broadcast_point:)

      playlist = create(:playlist, organization:)
      media_asset = create(:media_asset, :ready, :with_png_file, organization:)
      item = create(:playlist_item, playlist:, media_asset:, position: 1, display_duration_seconds: 10)

      schedule = create(
        :schedule_rule,
        organization:,
        playlist:,
        point_group:,
        starts_at: 1.hour.ago,
        ends_at: 1.hour.from_now
      )

      { broadcast_point:, playlist:, media_asset:, item:, schedule: }
    end

    it "returns the active assignment payload for a broadcast point" do
      scenario = build_active_assignment_scenario

      payload = described_class.call(broadcast_point: scenario[:broadcast_point], at: Time.current)

      expect(payload).to include(
        assignment_id: scenario[:schedule].id,
        starts_at: scenario[:schedule].starts_at.iso8601,
        ends_at: scenario[:schedule].ends_at.iso8601
      )
      expect(payload.dig(:playlist, :id)).to eq(scenario[:playlist].id)
      expect(payload.dig(:playlist, :items)).to contain_exactly(
        include(
          position: scenario[:item].position,
          kind: scenario[:media_asset].content_kind,
          duration_seconds: 10,
          media: include(
            id: scenario[:media_asset].id,
            mime_type: "image/png"
          )
        )
      )
    end

    it "returns nil when no active schedule exists" do
      broadcast_point = create(:broadcast_point)

      payload = described_class.call(broadcast_point:, at: Time.current)

      expect(payload).to be_nil
    end
  end
end
