# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: point_groups
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_point_groups_on_organization_id           (organization_id)
#  index_point_groups_on_organization_id_and_name  (organization_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
RSpec.describe PointGroup, type: :model do
  describe "validations" do
    it "requires a name" do
      group = build(:point_group, name: "")
      expect(group).not_to be_valid
    end

    it "enforces unique name per organization" do
      existing = create(:point_group, name: "North")
      dup = build(:point_group, organization: existing.organization, name: "North")
      expect(dup).not_to be_valid
    end
  end

  describe "memberships" do
    it "includes broadcast points via memberships" do
      org = create(:organization)
      group = create(:point_group, organization: org)
      point = create(:broadcast_point, organization: org)
      create(:point_group_membership, point_group: group, broadcast_point: point)
      expect(group.reload.broadcast_points).to contain_exactly(point)
    end
  end

  describe PointGroupMembership do
    it "rejects points from another organization" do
      group = create(:point_group)
      foreign_point = create(:broadcast_point)
      membership = build(:point_group_membership, point_group: group, broadcast_point: foreign_point)
      expect(membership).not_to be_valid
    end
  end
end
