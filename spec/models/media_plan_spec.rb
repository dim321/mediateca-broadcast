# frozen_string_literal: true

require 'rails_helper'

# == Schema Information
#
# Table name: media_plans
#
#  id                       :bigint           not null, primary key
#  ends_at                  :datetime         not null
#  starts_at                :datetime         not null
#  status                   :string           default("active"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  airtime_booking_id       :bigint           not null
#  broadcast_point_group_id :bigint           not null
#  organization_id          :bigint           not null
#  rotation_id              :bigint           not null
#
# Indexes
#
#  index_media_plans_on_airtime_booking_id                         (airtime_booking_id)
#  index_media_plans_on_broadcast_point_group_id                   (broadcast_point_group_id)
#  index_media_plans_on_organization_id                            (organization_id)
#  index_media_plans_on_organization_id_and_starts_at_and_ends_at  (organization_id,starts_at,ends_at)
#  index_media_plans_on_rotation_id                                (rotation_id)
#  index_media_plans_on_status                                     (status)
#
# Foreign Keys
#
#  fk_rails_...  (airtime_booking_id => airtime_bookings.id) ON DELETE => restrict
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id) ON DELETE => restrict
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
RSpec.describe MediaPlan, type: :model do
  let(:organization) { create(:organization, :client) }
  let(:rotation) { create(:rotation, organization: organization) }
  let(:screen) { create(:screen) }
  let(:broadcast_point_group) do
    create(:broadcast_point_group, organization: organization).tap do |group|
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    end
  end

  def booking_covering(starts_at, ends_at, group: broadcast_point_group, org: organization)
    seconds = (ends_at - starts_at).to_i
    create(
      :airtime_booking,
      organization: org,
      broadcast_point_group: group,
      starts_at: starts_at,
      ends_at: ends_at,
      seconds: seconds
    )
  end

  def build_plan(**attributes)
    starts = attributes.fetch(:starts_at, Time.utc(2026, 8, 10, 10, 0, 0))
    ends = attributes.fetch(:ends_at, Time.utc(2026, 8, 10, 12, 0, 0))
    group = attributes.fetch(:broadcast_point_group, broadcast_point_group)
    org = attributes.fetch(:organization, organization)
    booking = attributes.key?(:airtime_booking) ? attributes[:airtime_booking] : booking_covering(starts, ends, group: group, org: org)

    described_class.new(
      {
        organization: org,
        rotation: rotation,
        broadcast_point_group: group,
        starts_at: starts,
        ends_at: ends,
        airtime_booking: booking
      }.merge(attributes.except(:airtime_booking)).merge(airtime_booking: booking)
    )
  end

  it 'requires ends_at after starts_at' do
    booking = booking_covering(Time.utc(2026, 8, 10, 10, 0, 0), Time.utc(2026, 8, 10, 12, 0, 0))
    plan = described_class.new(
      organization: organization,
      rotation: rotation,
      broadcast_point_group: broadcast_point_group,
      airtime_booking: booking,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 9, 0, 0)
    )

    expect(plan).not_to be_valid
    expect(plan.errors[:ends_at]).to be_present
  end

  it 'requires the rotation and group to belong to the plan organization' do
    plan = build_plan(rotation: create(:rotation))

    expect(plan).not_to be_valid
    expect(plan.errors[:rotation]).to be_present
  end

  it 'rejects without a booking (AE4)' do
    plan = build_plan(airtime_booking: nil)

    expect(plan).not_to be_valid
    expect(plan.errors[:airtime_booking]).to be_present
  end

  it 'rejects when plan window exceeds booking (AE5)' do
    booking = booking_covering(Time.utc(2026, 8, 10, 10, 0, 0), Time.utc(2026, 8, 10, 11, 0, 0))
    plan = build_plan(
      airtime_booking: booking,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 11, 30, 0)
    )

    expect(plan).not_to be_valid
    expect(plan.errors[:base]).to include(I18n.t('activerecord.errors.models.media_plan.attributes.base.outside_booking_window'))
  end

  it 'rejects a foreign-org booking' do
    foreign = create(:organization, :client)
    foreign_group = create(:broadcast_point_group, organization: foreign)
    create(:broadcast_point_group_membership, broadcast_point_group: foreign_group, screen: create(:screen))
    foreign_booking = booking_covering(
      Time.utc(2026, 8, 10, 10, 0, 0),
      Time.utc(2026, 8, 10, 12, 0, 0),
      group: foreign_group,
      org: foreign
    )

    plan = build_plan(airtime_booking: foreign_booking)

    expect(plan).not_to be_valid
    expect(plan.errors[:airtime_booking]).to be_present
  end

  it 'allows adjacent windows for the same screen' do
    create(
      :media_plan,
      organization: organization,
      rotation: rotation,
      broadcast_point_group: broadcast_point_group,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
    )
    adjacent = build_plan(
      starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 14, 0, 0)
    )

    expect(adjacent).to be_valid
  end

  it 'rejects overlapping windows for a shared screen without persisting the second plan' do
    original = create(
      :media_plan,
      organization: organization,
      rotation: rotation,
      broadcast_point_group: broadcast_point_group,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
    )
    overlapping = build_plan(
      starts_at: Time.utc(2026, 8, 10, 11, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 13, 0, 0)
    )

    expect(overlapping).not_to be_valid
    expect(overlapping.errors[:base]).to include('overlaps an existing media plan')
    expect { overlapping.save! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(described_class.find(original.id).attributes).to include(original.attributes.slice('starts_at', 'ends_at'))
  end

  it 'allows cross-org overlapping windows on a shared screen (R10)' do
    create(
      :media_plan,
      organization: organization,
      rotation: rotation,
      broadcast_point_group: broadcast_point_group,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
    )

    other = create(:organization, :client)
    other_rotation = create(:rotation, organization: other)
    other_group = create(:broadcast_point_group, organization: other)
    create(:broadcast_point_group_membership, broadcast_point_group: other_group, screen: screen)
    other_plan = build_plan(
      organization: other,
      rotation: other_rotation,
      broadcast_point_group: other_group,
      starts_at: Time.utc(2026, 8, 10, 11, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 13, 0, 0)
    )

    expect(other_plan).to be_valid
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

  it 'accepts cancelled status' do
    plan = create(
      :media_plan,
      organization: organization,
      rotation: rotation,
      broadcast_point_group: broadcast_point_group
    )

    plan.status = :cancelled

    expect(plan).to be_valid
    expect(plan).to be_cancelled
  end

  it 'builds without an airtime quota' do
    plan = build(
      :media_plan,
      organization: organization,
      rotation: rotation,
      broadcast_point_group: broadcast_point_group
    )

    expect(plan.airtime_booking).to be_present
    expect(plan.airtime_booking).not_to respond_to(:airtime_quota)
    expect(plan).to be_valid
  end
end
