# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Avo users', type: :request do
  it 'shows password fields and hides organization_id on the new form' do
    organization = create(:organization, :operator)
    user = create(:user, organization:)

    sign_in_as(user)
    get '/avo/resources/users/new'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="user[password]"')
    expect(response.body).to include('name="user[password_confirmation]"')
    expect(response.body).to include('name="user[organization_id]"')
    expect(response.body).not_to match(/Organization id/i)
  end

  it 'creates a user with password and organization from belongs_to' do
    operator = create(:organization, :operator)
    target_organization = create(:organization, :client)
    user = create(:user, organization: operator)

    sign_in_as(user)
    expect {
      post '/avo/resources/users', params: {
        user: {
          email: 'new-user@example.com',
          password: 'password123456',
          password_confirmation: 'password123456',
          organization_id: target_organization.id
        }
      }
    }.to change(User, :count).by(1)

    created = User.find_by!(email: 'new-user@example.com')
    expect(created.organization).to eq(target_organization)
    expect(created.authenticate('password123456')).to eq(created)
  end
end
