# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StationPolicy do
  it 'denies client users from creating stations' do
    client_user = create(:user, organization: create(:organization, :client))
    station = create(:station, organization: create(:organization, :operator))

    expect(described_class.new(client_user, station)).not_to be_create
  end
end
