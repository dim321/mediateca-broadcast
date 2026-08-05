# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Avo airtime quotas', type: :request do
  it 'lets an operator create a quota on a client group' do
    operator = create(:user, organization: create(:organization, :operator))
    client = create(:organization, :client)
    group = create(:broadcast_point_group, organization: client)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen: create(:screen))

    sign_in_as(operator)
    expect do
      post '/avo/resources/airtime_quotas', params: {
        airtime_quota: {
          broadcast_point_group_id: group.id,
          starts_at: '2026-08-10 00:00:00',
          ends_at: '2026-08-11 00:00:00',
          seconds_total: 3600,
          seconds_remaining: 3600
        }
      }
    end.to change(AirtimeQuota, :count).by(1)

    expect(response).to have_http_status(:redirect).or have_http_status(:ok)
  end

  it 'lists quotas for an operator' do
    operator = create(:user, organization: create(:organization, :operator))
    create(:airtime_quota, :with_screen)
    sign_in_as(operator)

    get '/avo/resources/airtime_quotas'
    expect(response).to have_http_status(:ok)
  end
end
