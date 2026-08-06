# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin media plans', type: :request do
  let(:client) { create(:organization, :client) }
  let(:group) { create(:broadcast_point_group, organization: client) }
  let(:screen) { create(:screen) }
  let!(:membership) { create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen) }
  let(:rotation) { create(:rotation, organization: client) }
  let(:plan) do
    Airtime::OccupyWithPlan.call(
      organization: client,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: Time.utc(2026, 8, 10, 10, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 11, 0, 0)
    )
  end

  it 'roots admin at media plans and has no Quotas nav' do
    get admin_root_path

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include('Airtime quotas')
    expect(response.body).not_to include('Airtime Quotas')
    expect(response.body).to match(/Media [Pp]lans/)
  end

  it 'lets an operator cancel a client plan and free the slot' do
    delete cancel_admin_media_plan_path(plan)

    expect(response).to redirect_to(admin_media_plans_path)
    expect(plan.reload).to be_cancelled
    expect(plan.airtime_booking.reload).to be_cancelled
  end

  it 'keeps the original plan when reschedule conflicts' do
    Airtime::OccupyWithPlan.call(
      organization: client,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: Time.utc(2026, 8, 10, 12, 0, 0),
      ends_at: Time.utc(2026, 8, 10, 13, 0, 0)
    )
    original_starts = plan.starts_at

    patch reschedule_admin_media_plan_path(plan), params: {
      broadcast_point_group_id: group.id,
      starts_at: '2026-08-10T12:00',
      ends_at: '2026-08-10T13:00'
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(plan.reload.starts_at).to eq(original_starts)
  end

  it 'has no route to airtime quotas (AE6)' do
    expect do
      Rails.application.routes.recognize_path('/admin/airtime_quotas', method: :get)
    end.to raise_error(ActionController::RoutingError)
  end
end
