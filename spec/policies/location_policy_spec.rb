# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationPolicy do
  let(:operator_organization) { create(:organization, :operator) }
  let(:client_organization) { create(:organization, :client) }
  let(:operator_user) { create(:user, organization: operator_organization) }
  let(:client_user) { create(:user, organization: client_organization) }
  let(:location) { create(:location, organization: operator_organization) }

  it 'allows an operator to manage its locations' do
    policy = described_class.new(operator_user, location)

    expect(policy).to be_index
    expect(policy).to be_show
    expect(policy).to be_create
    expect(policy).to be_update
    expect(policy).to be_destroy
  end

  it 'denies client users from creating locations' do
    expect(described_class.new(client_user, location)).not_to be_create
  end

  it 'scopes locations to the operator organization' do
    foreign_location = create(:location, organization: create(:organization, :operator))

    resolved = described_class::Scope.new(operator_user, Location.all).resolve

    expect(resolved).to contain_exactly(location)
    expect(resolved).not_to include(foreign_location)
  end
end
