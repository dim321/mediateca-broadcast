# frozen_string_literal: true

require 'rails_helper'

# == Schema Information
#
# Table name: broadcast_point_groups
#
#  id                       :bigint           not null, primary key
#  commercial_quota_percent :integer
#  commercial_quota_period  :string
#  name                     :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  organization_id          :bigint           not null
#
# Indexes
#
#  index_broadcast_point_groups_on_organization_id           (organization_id)
#  index_broadcast_point_groups_on_organization_id_and_name  (organization_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
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
    it 'allows a client group to include a fleet screen' do
      client = create(:organization, :client)
      group = create(:broadcast_point_group, organization: client)
      screen = create(:screen)

      membership = build(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect(membership).to be_valid
    end

    it 'does not add the same screen twice' do
      group = create(:broadcast_point_group)
      screen = create(:screen)
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      duplicate = build(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)

      expect(duplicate).not_to be_valid
    end

    it 'rejects a screen that overlaps an existing media plan' do
      organization = create(:organization, :client)
      screen = create(:screen)
      create_plan_covering(organization:, screen:, starts_at: Time.utc(2026, 8, 10, 10), ends_at: Time.utc(2026, 8, 10, 12))
      target_group = create_group_with_plan(organization:, starts_at: Time.utc(2026, 8, 10, 11), ends_at: Time.utc(2026, 8, 10, 13))

      membership = target_group.broadcast_point_group_memberships.new(screen:)

      expect(membership).not_to be_valid
      expect(membership.errors[:screen]).to include('overlaps an existing media plan for this screen')
    end
  end

  describe 'commercial quota' do
    let(:owner) { create(:organization, :client) }
    let(:location) do
      create(
        :location,
        operating_hours: {
          "mon" => [ { "start" => "00:00", "end" => "23:59" } ],
          "tue" => [ { "start" => "00:00", "end" => "23:59" } ],
          "wed" => [ { "start" => "00:00", "end" => "23:59" } ],
          "thu" => [ { "start" => "00:00", "end" => "23:59" } ],
          "fri" => [ { "start" => "00:00", "end" => "23:59" } ],
          "sat" => [ { "start" => "00:00", "end" => "23:59" } ],
          "sun" => [ { "start" => "00:00", "end" => "23:59" } ]
        }
      )
    end
    let(:screen) { create(:screen, station: create(:station, location: location), owner_organization: owner) }
    let(:group) do
      create(:broadcast_point_group, organization: owner).tap do |g|
        create(:broadcast_point_group_membership, broadcast_point_group: g, screen: screen)
      end
    end

    it 'rejects quota on a heterogeneous owner group (AE3)' do
      other = create(:organization, :client)
      other_screen = create(:screen, owner_organization: other)
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: other_screen)

      group.commercial_quota_percent = 60
      group.commercial_quota_period = :hour

      expect(group).not_to be_valid
      expect(group.errors[:base]).to be_present
    end

    it 'rejects quota when location hours are missing (AE6)' do
      bare = create(:location, operating_hours: {})
      owned = create(:screen, station: create(:station, location: bare), owner_organization: owner)
      bare_group = create(:broadcast_point_group, organization: owner)
      create(:broadcast_point_group_membership, broadcast_point_group: bare_group, screen: owned)

      bare_group.commercial_quota_percent = 60
      bare_group.commercial_quota_period = :hour

      expect(bare_group).not_to be_valid
    end

    it 'allows set, update, and clear when homogeneous with hours' do
      group.commercial_quota_percent = 60
      group.commercial_quota_period = :hour
      expect(group.save).to be(true)

      group.update!(commercial_quota_percent: 40)
      expect(group.reload.commercial_quota_percent).to eq(40)

      group.update!(commercial_quota_percent: nil, commercial_quota_period: nil)
      expect(group.reload.commercial_quota_configured?).to be(false)
    end
  end

  private

  def create_plan_covering(organization:, screen:, starts_at:, ends_at:)
    group = create(:broadcast_point_group, organization:)
    create(:broadcast_point_group_membership, broadcast_point_group: group, screen:)
    create(:media_plan, organization:, broadcast_point_group: group, starts_at:, ends_at:)
  end

  def create_group_with_plan(organization:, starts_at:, ends_at:)
    group = create(:broadcast_point_group, organization:)
    create(:media_plan, organization:, broadcast_point_group: group, starts_at:, ends_at:)
    group
  end
end
