# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnedBroadcastPointGroupPolicy do
  let(:organization) { create(:organization, :client) }
  let(:manager) { create(:user, :manager, organization: organization) }
  let(:accountant) { create(:user, :accountant, organization: organization) }
  let(:group) { create(:broadcast_point_group, organization: organization) }
  let(:other_group) { create(:broadcast_point_group, organization: create(:organization, :client)) }

  it 'allows manager to manage own org group' do
    policy = described_class.new(manager, group)
    expect(policy).to be_index
    expect(policy).to be_show
    expect(policy).to be_create
    expect(policy).to be_update
    expect(policy).to be_add_screens
    expect(policy).to be_remove_member
  end

  it 'denies accountant and foreign group show' do
    expect(described_class.new(accountant, group)).not_to be_index
    expect(described_class.new(manager, other_group)).not_to be_show
  end

  it 'scopes to organization groups' do
    group
    other_group
    resolved = described_class::Scope.new(manager, BroadcastPointGroup.all).resolve
    expect(resolved).to contain_exactly(group)
  end
end
