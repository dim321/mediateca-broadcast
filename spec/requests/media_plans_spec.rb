# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MediaPlans', type: :request do
  let(:user) { create(:user, organization: create(:organization, :client)) }
  let(:organization) { user.organization }
  let(:rotation) { create(:rotation, organization: organization) }
  let(:screen) { create(:screen) }
  let(:broadcast_point_group) do
    create(:broadcast_point_group, organization: organization).tap do |group|
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    end
  end
  let!(:booking) do
    quota = create(
      :airtime_quota,
      broadcast_point_group: broadcast_point_group,
      starts_at: Time.utc(2026, 8, 9),
      ends_at: Time.utc(2026, 8, 12),
      seconds_total: 86_400
    )
    create(
      :airtime_booking,
      organization: organization,
      broadcast_point_group: broadcast_point_group,
      airtime_quota: quota,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 12, 0, 0),
      seconds: 7_200
    )
  end

  def media_plan_params(starts: '2026-08-10T10:00', ends: '2026-08-10T12:00', booking_id: booking.id)
    {
      media_plan: {
        rotation_id: rotation.id,
        airtime_booking_id: booking_id,
        starts_at: starts,
        ends_at: ends
      }
    }
  end

  describe 'GET /media_plans' do
    it 'lists plans in the client organization' do
      sign_in_as(user)
      plan = create(
        :media_plan,
        organization: organization,
        rotation: rotation,
        broadcast_point_group: broadcast_point_group,
        airtime_booking: booking,
        starts_at: booking.starts_at,
        ends_at: booking.ends_at
      )

      get media_plans_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(plan.rotation.name)
      expect(response.body).to include(plan.broadcast_point_group.name)
    end
  end

  describe 'POST /media_plans' do
    before { sign_in_as(user) }

    it 'creates a plan with a ready rotation and booking' do
      asset = create(:media_asset, :ready, :with_png_file, organization: organization)
      create(:rotation_item, rotation: rotation, media_asset: asset)

      expect do
        post media_plans_path, params: media_plan_params
      end.to change(MediaPlan, :count).by(1)

      expect(response).to redirect_to(media_plans_path)
      expect(MediaPlan.last.airtime_booking).to eq(booking)
    end

    it 'rejects without booking (AE4)' do
      asset = create(:media_asset, :ready, :with_png_file, organization: organization)
      create(:rotation_item, rotation: rotation, media_asset: asset)

      expect do
        post media_plans_path, params: media_plan_params(booking_id: nil)
      end.not_to change(MediaPlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects an overlap and leaves the original plan unchanged' do
      original = create(
        :media_plan,
        organization: organization,
        rotation: rotation,
        broadcast_point_group: broadcast_point_group,
        airtime_booking: booking,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 11, 0, 0)
      )

      expect do
        post media_plans_path, params: media_plan_params(starts: '2026-08-10T10:30', ends: '2026-08-10T11:30')
      end.not_to change(MediaPlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(original.reload.starts_at).to eq(Time.utc(2026, 8, 10, 10, 0, 0))
    end

    it 'rejects a rotation containing a processing asset' do
      asset = create(:media_asset, :ready, :with_png_file, organization: organization)
      create(:rotation_item, rotation: rotation, media_asset: asset)
      asset.update_column(:processing_status, 'processing')

      expect do
        post media_plans_path, params: media_plan_params
      end.not_to change(MediaPlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
