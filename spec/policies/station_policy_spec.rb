# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StationPolicy do
  it 'denies client users from creating stations' do
    client_user = create(:user, organization: create(:organization, :client))
    station = create(:station)

    expect(described_class.new(client_user, station)).not_to be_create
  end

  it 'allows operator users to manage stations' do
    operator_user = create(:user, organization: create(:organization, :operator))
    station = create(:station)

    expect(described_class.new(operator_user, station)).to be_create
    expect(described_class.new(operator_user, station)).to be_update
  end
end
