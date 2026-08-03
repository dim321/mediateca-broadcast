# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Agent::V1::Packages', type: :request do
  describe 'GET /api/agent/v1/package' do
    it 'returns broadcast media for active plans on this station only' do
      client = create(:organization, :client)
      operator = create(:organization, :operator)
      station = create(:station, organization: operator)
      screen = create(:screen, organization: operator, station:)
      token = station.assign_agent_token!
      media_asset, rotation = create_rotation(client)
      plan = create_plan(organization: client, rotation:, screen:)
      create_plan(organization: client, rotation:, screen: create(:screen, organization: operator))

      get '/api/agent/v1/package', headers: agent_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers['ETag']).to be_present
      expect(response.parsed_body).to include('version', 'etag', 'items', 'screen_map')
      expect(response.parsed_body['items']).to contain_exactly(item_for(plan, screen, media_asset))
      expect(response.parsed_body['screen_map']).to eq(screen.id.to_s => [ plan.id ])
    end

    it 'returns an empty package for a station without matching plans' do
      token = SecureRandom.hex(16)
      station = create(:station, organization: create(:organization, :operator))
      station.assign_agent_token!(token)

      get '/api/agent/v1/package', headers: agent_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['items']).to eq([])
      expect(response.parsed_body['screen_map']).to eq({})
    end

    it 'returns 401 without a valid agent token' do
      get '/api/agent/v1/package', as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('error' => 'unauthorized')
    end
  end

  private

  def create_rotation(organization)
    media_asset = create_broadcast_video(organization)
    rotation = create(:rotation, organization:)
    create(:rotation_item, rotation:, media_asset:, position: 1)
    [ media_asset, rotation ]
  end

  def create_plan(organization:, rotation:, screen:)
    group = create(:broadcast_point_group, organization:)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen:)
    create(
      :media_plan,
      organization:,
      rotation:,
      broadcast_point_group: group,
      starts_at: 1.hour.ago,
      ends_at: 1.hour.from_now
    )
  end

  def item_for(plan, screen, media_asset)
    include(
      'media_plan_id' => plan.id,
      'screen_ids' => [ screen.id ],
      'rotation' => include(
        'items' => [
          include(
            'position' => 1,
            'media' => include(
              'id' => media_asset.id,
              'url' => include('rails/active_storage/blobs'),
              'mime_type' => 'video/mp2t'
            )
          )
        ]
      )
    )
  end

  def create_broadcast_video(organization)
    media_asset = build(:media_asset, :ready, organization:)
    media_asset.file.attach(
      io: StringIO.new('source video'),
      filename: 'clip.mp4',
      content_type: 'video/mp4'
    )
    media_asset.save!
    media_asset.broadcast_file.attach(
      io: StringIO.new('transport stream'),
      filename: 'clip.ts',
      content_type: 'video/mp2t'
    )
    media_asset
  end
end
