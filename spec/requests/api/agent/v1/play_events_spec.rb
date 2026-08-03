# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Agent::V1::PlayEvents', type: :request do
  describe 'POST /api/agent/v1/play_events' do
    it 'records a start event as a play log' do
      station = create(:station)
      token = station.assign_agent_token!
      screen = create(:screen, organization: station.organization, station:)
      media_asset = create(:media_asset, :ready, :with_png_file, organization: station.organization)
      started_at = Time.utc(2026, 8, 3, 3, 0, 0)

      expect do
        post_play_event(screen:, media_asset:, started_at:, token:)
      end.to change(PlayLog, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('play_log_ids' => [ PlayLog.last.id ])
      expect(PlayLog.last).to have_attributes(
        organization: media_asset.organization,
        screen:,
        media_asset:,
        started_at:,
        source: 'agent'
      )
    end

    it 'rejects events for a screen on another station' do
      station = create(:station)
      token = station.assign_agent_token!
      other_screen = create(:screen, organization: station.organization)
      media_asset = create(:media_asset, :ready, :with_png_file, organization: station.organization)

      expect do
        post_play_event(screen: other_screen, media_asset:, started_at: Time.current, token:)
      end.not_to change(PlayLog, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 without an agent token' do
      post '/api/agent/v1/play_events', params: { events: [] }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  private

  def post_play_event(screen:, media_asset:, started_at:, token:)
    post '/api/agent/v1/play_events',
      params: {
        events: [ {
          screen_id: screen.id,
          media_asset_id: media_asset.id,
          started_at: started_at.iso8601
        } ]
      },
      headers: agent_authorization_headers(token),
      as: :json
  end
end
