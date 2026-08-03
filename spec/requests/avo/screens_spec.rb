# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Avo screens', type: :request do
  it 'lists only screens from the signed-in operator organization' do
    organization = create(:organization, :operator)
    user = create(:user, organization:)
    screen = create(:screen, organization:)
    foreign_screen = create(:screen, organization: create(:organization, :operator))

    sign_in_as(user)
    get '/avo/resources/screens'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(screen.name)
    expect(response.body).not_to include(foreign_screen.name)
  end
end
