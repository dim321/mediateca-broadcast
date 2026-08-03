# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BroadcastPointGroup, type: :model do
  describe 'validations' do
    it 'requires a name' do
      group = build(:broadcast_point_group, name: '')

      expect(group).not_to be_valid
    end

    it 'enforces a unique name per client organization' do
      existing = create(:broadcast_point_group, name: 'North screens')
      duplicate = build(:broadcast_point_group, organization: existing.organization, name: 'North screens')

      expect(duplicate).not_to be_valid
    end
  end

  describe 'memberships' do
    it 'allows a client group to include an operator-owned screen' do
      client = create(:organization, :client)
      operator = create(:organization, :operator)
      group = create(:broadcast_point_group, organization: client)
      screen = create(:screen, organization: operator)

      membership = build(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect(membership).to be_valid
    end

    it 'does not add the same screen twice' do
      group = create(:broadcast_point_group)
      screen = create(:screen, organization: create(:organization, :operator))
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      duplicate = build(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect(duplicate).not_to be_valid
    end

    it 'rejects screens that do not belong to an operator organization' do
      group = create(:broadcast_point_group)
      screen = create(:screen, organization: create(:organization, :client))

      membership = build(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect(membership).not_to be_valid
      expect(membership.errors[:screen]).to be_present
    end
  end
end
