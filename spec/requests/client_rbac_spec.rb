# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client LK RBAC', type: :request do
  let(:organization) { create(:organization, :client) }
  let(:accountant) { create(:user, :accountant, organization: organization) }
  let(:manager) { create(:user, :manager, organization: organization) }

  describe 'accountant denials (AE7 / KTD11)' do
    before { sign_in_as(accountant) }

    it 'denies GET media_plans index' do
      get media_plans_path

      expect(response).to redirect_to(rails_health_check_path)
      expect(flash[:alert]).to be_present
    end

    it 'denies POST media_plans' do
      expect do
        post media_plans_path, params: {
          media_plan: {
            rotation_id: create(:rotation, organization: organization).id,
            broadcast_point_group_id: create(:broadcast_point_group, organization: organization).id,
            starts_at: '2026-08-10T10:00',
            ends_at: '2026-08-10T12:00'
          }
        }
      end.not_to change(MediaPlan, :count)

      expect(response).to redirect_to(rails_health_check_path)
      expect(flash[:alert]).to be_present
    end

    it 'denies POST rotations' do
      expect do
        post rotations_path, params: { rotation: { name: 'Blocked' } }
      end.not_to change(Rotation, :count)

      expect(flash[:alert]).to be_present
    end
  end

  describe 'manager default CRUD' do
    before { sign_in_as(manager) }

    it 'allows GET media_plans' do
      get media_plans_path
      expect(response).to have_http_status(:success)
    end
  end

  describe 'role assignment surface' do
    it 'exposes no non-Avo users controller for client role self-service' do
      expect(File).not_to exist(Rails.root.join('app/controllers/users_controller.rb'))
    end
  end
end
