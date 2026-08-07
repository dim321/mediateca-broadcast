# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationPolicy do
  let(:operator_user) { create(:user, organization: create(:organization, :operator)) }
  let(:client_user) { create(:user, :manager, organization: create(:organization, :client)) }
  let(:location) { create(:location) }

  it 'allows an operator to manage locations' do
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

  it 'allows client managers read-only access' do
    expect(described_class.new(client_user, location)).to be_show
  end

  it 'scopes all locations to operator users' do
    other_location = create(:location)

    resolved = described_class::Scope.new(operator_user, Location.all).resolve

    expect(resolved).to include(location, other_location)
  end

  it 'scopes all locations to client managers for read-only catalog' do
    other_location = create(:location)

    resolved = described_class::Scope.new(client_user, Location.all).resolve

    expect(resolved).to include(location, other_location)
  end
end
