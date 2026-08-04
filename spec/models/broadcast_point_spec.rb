# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: broadcast_points
#
#  id                  :bigint           not null, primary key
#  city                :string
#  device_token_digest :string
#  name                :string           not null
#  status              :string           default("unknown"), not null
#  time_zone           :string
#  venue_label         :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  organization_id     :bigint           not null
#
# Indexes
#
#  index_broadcast_points_on_organization_id             (organization_id)
#  index_broadcast_points_on_organization_id_and_status  (organization_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
RSpec.describe BroadcastPoint, type: :model do
  describe "validations" do
    it "requires a name" do
      point = build(:broadcast_point, name: "")
      expect(point).not_to be_valid
      expect(point.errors[:name]).to be_present
    end
  end

  describe "associations" do
    it "can have many tags through broadcast_point_tags" do
      org = create(:organization)
      point = create(:broadcast_point, organization: org)
      tag_a = create(:tag, organization: org, name: "alpha")
      tag_b = create(:tag, organization: org, name: "beta")
      point.tags << tag_a
      point.tags << tag_b
      expect(point.reload.tags.pluck(:name)).to contain_exactly("alpha", "beta")
    end
  end

  describe "status enum" do
    it "defaults to unknown" do
      expect(create(:broadcast_point).status).to eq("unknown")
    end
  end

  describe BroadcastPointTag do
    it "rejects tags from another organization" do
      point = create(:broadcast_point)
      foreign_tag = create(:tag)
      join = build(:broadcast_point_tag, broadcast_point: point, tag: foreign_tag)
      expect(join).not_to be_valid
    end
  end
end
