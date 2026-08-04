# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Avo tenant resources', type: :request do
  it 'lets an operator list client organizations and their media' do
    operator = create(:user, organization: create(:organization, :operator))
    client = create(:organization, :client, name: 'Acme Client')
    asset = create(:media_asset, :with_png_file, organization: client)

    sign_in_as(operator)

    get '/avo/resources/organizations'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(client.name)

    get '/avo/resources/media_assets'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(asset.id.to_s)
  end
end
