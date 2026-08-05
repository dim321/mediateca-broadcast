# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Avo airtime bookings', type: :request do
  it 'lists client bookings for an operator' do
    operator = create(:user, organization: create(:organization, :operator))
    booking = create(:airtime_booking)
    sign_in_as(operator)

    get '/avo/resources/airtime_bookings'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(booking.organization.name).or include(booking.id.to_s)
  end
end
