# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Avo screens', type: :request do
  it 'lists all fleet screens for a signed-in operator' do
    organization = create(:organization, :operator)
    user = create(:user, organization:)
    screen = create(:screen)
    other_screen = create(:screen)

    sign_in_as(user)
    get '/avo/resources/screens'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(screen.name)
    expect(response.body).to include(other_screen.name)
  end

  it 'denies access to client users' do
    user = create(:user, organization: create(:organization, :client))

    sign_in_as(user)
    get '/avo/resources/screens'

    expect(response).to redirect_to('/')
  end
end
