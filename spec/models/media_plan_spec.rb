# frozen_string_literal: true

require 'rails_helper'

# == Schema Information
#
# Table name: media_plans
#
#  id                       :bigint           not null, primary key
#  ends_at                  :datetime         not null
#  starts_at                :datetime         not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  broadcast_point_group_id :bigint           not null
#  organization_id          :bigint           not null
#  rotation_id              :bigint           not null
#
# Indexes
#
#  index_media_plans_on_broadcast_point_group_id                   (broadcast_point_group_id)
#  index_media_plans_on_organization_id                            (organization_id)
#  index_media_plans_on_organization_id_and_starts_at_and_ends_at  (organization_id,starts_at,ends_at)
#  index_media_plans_on_rotation_id                                (rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id) ON DELETE => restrict
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
RSpec.describe MediaPlan, type: :model do
  let(:organization) { create(:organization, :client) }
  let(:rotation) { create(:rotation, organization: organization) }
  let(:screen) { create(:screen, organization: create(:organization, :operator)) }
  let(:broadcast_point_group) do
    create(:broadcast_point_group, organization: organization).tap do |group|
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    end
  end

  def build_plan(**attributes)
    described_class.new(
      {
        organization: organization,
        rotation: rotation,
        broadcast_point_group: broadcast_point_group,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
      }.merge(attributes)
    )
  end

  def plan_attributes
    {
      organization: organization,
      rotation: rotation,
      broadcast_point_group: broadcast_point_group,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
    }
  end

  it 'requires ends_at after starts_at' do
    plan = build_plan(ends_at: Time.utc(2026, 8, 10, 9, 0, 0))

    expect(plan).not_to be_valid
    expect(plan.errors[:ends_at]).to be_present
  end

  it 'requires the rotation and group to belong to the plan organization' do
    plan = build_plan(rotation: create(:rotation))

    expect(plan).not_to be_valid
    expect(plan.errors[:rotation]).to be_present
  end

  it 'allows adjacent windows for the same screen' do
    create(:media_plan, **plan_attributes)
    adjacent = build_plan(
      starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 14, 0, 0)
    )

    expect(adjacent).to be_valid
  end

  it 'rejects overlapping windows for a shared screen without persisting the second plan' do
    original = create(:media_plan, **plan_attributes)
    overlapping = build_plan(
      starts_at: Time.utc(2026, 8, 10, 11, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 13, 0, 0)
    )

    expect(overlapping).not_to be_valid
    expect(overlapping.errors[:base]).to include('overlaps an existing media plan')
    expect { overlapping.save! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(described_class.find(original.id).attributes).to include(original.attributes)
  end

  it 'rejects a rotation that contains processing media' do
    media_asset = create(:media_asset, :ready, :with_png_file, organization: organization)
    create(:rotation_item, rotation: rotation, media_asset: media_asset)
    media_asset.update_column(:processing_status, 'processing')

    plan = build_plan

    expect(plan).not_to be_valid
    expect(plan.errors[:rotation]).to include('must contain only broadcast-ready media')
  end

  it 'requires a broadcast file for ready videos' do
    media_asset = create(:media_asset, :ready, :with_png_file, organization: organization)
    media_asset.update_column(:content_kind, 'video')
    create(:rotation_item, rotation: rotation, media_asset: media_asset)

    plan = build_plan

    expect(plan).not_to be_valid
    expect(plan.errors[:rotation]).to include('must contain only broadcast-ready media')
  end

  it 'accepts a ready non-video media asset without a broadcast file' do
    media_asset = create(:media_asset, :ready, :with_png_file, organization: organization)
    create(:rotation_item, rotation: rotation, media_asset: media_asset)

    expect(build_plan).to be_valid
  end
end
