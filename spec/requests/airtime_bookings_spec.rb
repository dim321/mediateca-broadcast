# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AirtimeBookings', type: :request do
  let(:organization) { create(:organization, :client) }
  let(:manager) { create(:user, :manager, organization: organization) }
  let(:group) { create(:broadcast_point_group, organization: organization) }
  let(:screen) { create(:screen) }
  let!(:membership) { create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen) }
  let!(:quota) do
    create(
      :airtime_quota,
      broadcast_point_group: group,
      starts_at: Time.utc(2026, 8, 10, 0, 0, 0),
      ends_at: Time.utc(2026, 8, 11, 0, 0, 0),
      seconds_total: 3_600
    )
  end

  def booking_params(starts: '2026-08-10T10:00', ends: '2026-08-10T10:10', quota_id: quota.id)
    {
      airtime_booking: {
        airtime_quota_id: quota_id,
        starts_at: starts,
        ends_at: ends
      }
    }
  end

  describe 'manager happy path' do
    before { sign_in_as(manager) }

    it 'books and lists own bookings' do
      expect do
        post airtime_bookings_path, params: booking_params
      end.to change(AirtimeBooking, :count).by(1)

      expect(response).to redirect_to(airtime_booking_path(AirtimeBooking.last))
      follow_redirect!
      expect(response.body).to include(group.name)

      get airtime_bookings_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(group.name)
    end

    it 'shows occupied slots without foreign org identifiers' do
      other = create(:organization, :client)
      other_group = create(:broadcast_point_group, organization: other)
      create(:broadcast_point_group_membership, broadcast_point_group: other_group, screen: screen)
      other_quota = create(
        :airtime_quota,
        broadcast_point_group: other_group,
        starts_at: quota.starts_at,
        ends_at: quota.ends_at,
        seconds_total: 3_600
      )
      Airtime::Book.call(
        quota: other_quota,
        organization: other,
        starts_at: Time.utc(2026, 8, 10, 9, 0, 0),
        ends_at: Time.utc(2026, 8, 10, 9, 10, 0)
      )

      get new_airtime_booking_path, params: { airtime_booking: { airtime_quota_id: quota.id } }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t('airtime_bookings.occupied_slots.occupied'))
      expect(response.body).not_to include(other.name)
      expect(response.body).not_to include("airtime_booking_#{AirtimeBooking.last.id}")
    end
  end

  describe 'denials' do
    it 'denies accountant book (AE7)' do
      accountant = create(:user, :accountant, organization: organization)
      sign_in_as(accountant)

      expect do
        post airtime_bookings_path, params: booking_params
      end.not_to change(AirtimeBooking, :count)

      expect(flash[:alert]).to be_present
    end

    it 'does not book a foreign org quota' do
      sign_in_as(manager)
      foreign_org = create(:organization, :client)
      foreign_group = create(:broadcast_point_group, organization: foreign_org)
      create(:broadcast_point_group_membership, broadcast_point_group: foreign_group, screen: create(:screen))
      foreign_quota = create(:airtime_quota, broadcast_point_group: foreign_group)

      expect do
        post airtime_bookings_path, params: booking_params(quota_id: foreign_quota.id)
      end.not_to change(AirtimeBooking, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'does not cancel a foreign booking (IDOR)' do
      sign_in_as(manager)
      foreign = create(:airtime_booking)

      delete cancel_airtime_booking_path(foreign)

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload).to be_confirmed
    end
  end
end
