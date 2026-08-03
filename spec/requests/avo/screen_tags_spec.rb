# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Avo screen tags', type: :request do
  it 'lets an operator create a tag and attach it to a screen' do
    organization = create(:organization, :operator)
    user = create(:user, organization:)
    screen = create(:screen, organization:)

    sign_in_as(user)

    post '/avo/resources/tags', params: {
      tag: {
        name: 'Lobby',
        organization_id: organization.id
      }
    }

    tag = Tag.find_by!(name: 'Lobby', organization:)
    expect(response).to redirect_to(%r{/avo/resources/tags})

    post '/avo/resources/screen_tags', params: {
      screen_tag: {
        screen_id: screen.id,
        tag_id: tag.id
      }
    }

    expect(screen.reload.tags).to contain_exactly(tag)
  end
end
