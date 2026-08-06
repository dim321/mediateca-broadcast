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

  def media_plan_params(starts: '2026-08-10T10:00', ends: '2026-08-10T12:00', group_id: broadcast_point_group.id)
    {
      media_plan: {
        rotation_id: rotation.id,
        broadcast_point_group_id: group_id,
        starts_at: starts,
        ends_at: ends
      }
    }
  end

  describe 'GET /media_plans' do
    it 'lists active plans in the client organization' do
      sign_in_as(user)
      plan = Airtime::OccupyWithPlan.call(
        organization: organization,
        broadcast_point_group: broadcast_point_group,
        rotation: rotation,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
      )

      get media_plans_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(plan.rotation.name)
      expect(response.body).to include(plan.broadcast_point_group.name)
    end

    it 'hides cancelled plans from the default index' do
      sign_in_as(user)
      plan = Airtime::OccupyWithPlan.call(
        organization: organization,
        broadcast_point_group: broadcast_point_group,
        rotation: rotation,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
      )
      Airtime::Cancel.call(plan: plan)

      get media_plans_path

      expect(response.body).not_to include(plan.rotation.name)
    end
  end

  describe 'POST /media_plans' do
    before { sign_in_as(user) }

    it 'creates a plan and occupies the slot without a prior booking' do
      asset = create(:media_asset, :ready, :with_png_file, organization: organization)
      create(:rotation_item, rotation: rotation, media_asset: asset)

      expect do
        post media_plans_path, params: media_plan_params
      end.to change(MediaPlan, :count).by(1)
        .and change(AirtimeBooking.confirmed, :count).by(1)

      expect(response).to redirect_to(media_plans_path)
      expect(MediaPlan.last.airtime_booking).to be_confirmed
    end

    it 'rejects an overlap with conflict status' do
      Airtime::OccupyWithPlan.call(
        organization: organization,
        broadcast_point_group: broadcast_point_group,
        rotation: rotation,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 11, 0, 0)
      )
      asset = create(:media_asset, :ready, :with_png_file, organization: organization)
      create(:rotation_item, rotation: rotation, media_asset: asset)

      expect do
        post media_plans_path, params: media_plan_params(starts: '2026-08-10T10:30', ends: '2026-08-10T11:30')
      end.not_to change(MediaPlan.active, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('screen slot already booked')
    end

    it 'renders occupancy without foreign org ids' do
      other = create(:organization, :client, name: 'ForeignOrgXYZ-NeverLeak')
      other_group = create(:broadcast_point_group, organization: other)
      create(:broadcast_point_group_membership, broadcast_point_group: other_group, screen: screen)
      Airtime::OccupyWithPlan.call(
        organization: other,
        broadcast_point_group: other_group,
        rotation: create(:rotation, organization: other),
        starts_at: Time.utc(2026, 8, 10, 9, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 9, 30, 0)
      )

      get new_media_plan_path, params: { media_plan: { broadcast_point_group_id: broadcast_point_group.id } }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t('media_plans.occupied_slots.heading'))
      expect(response.body).to include('Occupied')
      expect(response.body).not_to include('ForeignOrgXYZ-NeverLeak')
      expect(response.body).not_to include('airtime_booking_id')
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

  describe 'PATCH /media_plans/:id' do
    before { sign_in_as(user) }

    it 'updates rotation without changing the window' do
      plan = Airtime::OccupyWithPlan.call(
        organization: organization,
        broadcast_point_group: broadcast_point_group,
        rotation: rotation,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
      )
      other_rotation = create(:rotation, organization: organization)
      asset = create(:media_asset, :ready, :with_png_file, organization: organization)
      create(:rotation_item, rotation: other_rotation, media_asset: asset)

      patch media_plan_path(plan), params: { media_plan: { rotation_id: other_rotation.id } }

      expect(response).to redirect_to(media_plans_path)
      expect(plan.reload.rotation).to eq(other_rotation)
      expect(plan.starts_at).to eq(Time.utc(2026, 8, 10, 10, 0, 0))
      expect(plan.ends_at).to eq(Time.utc(2026, 8, 10, 12, 0, 0))
    end
  end

  describe 'DELETE /media_plans/:id/cancel' do
    before { sign_in_as(user) }

    it 'soft-cancels the plan and frees the slot' do
      plan = Airtime::OccupyWithPlan.call(
        organization: organization,
        broadcast_point_group: broadcast_point_group,
        rotation: rotation,
        starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 12, 0, 0)
      )

      delete cancel_media_plan_path(plan)

      expect(response).to redirect_to(media_plans_path)
      expect(plan.reload).to be_cancelled
      expect(plan.airtime_booking.reload).to be_cancelled
    end
  end
end
