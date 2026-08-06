# frozen_string_literal: true

module Fleet
  # LK read-only on-air view for a screen (org-scoped MediaPlan queries only).
  class ScreensController < ApplicationController
    before_action :require_user

    def index
      authorize Screen
      @screens = policy_scope(Screen).includes(:station).order(:name)
    end

    def show
      @screen = policy_scope(Screen).find(params[:id])
      authorize @screen
      @media_plans = on_air_plans_for(@screen)
    end

    private

    def require_user
      return if Current.user

      redirect_to login_path, alert: t("media_assets.authentication_required")
    end

    def on_air_plans_for(screen)
      # Org-scoped only — clients must not see other orgs' air blocks (R13 / AE6).
      policy_scope(MediaPlan)
        .active
        .joins(:airtime_booking)
        .joins(broadcast_point_group: :screens)
        .merge(AirtimeBooking.confirmed)
        .where(screens: { id: screen.id })
        .where("airtime_bookings.starts_at <= media_plans.starts_at AND airtime_bookings.ends_at >= media_plans.ends_at")
        .includes(:rotation, :broadcast_point_group, :airtime_booking)
        .order(:starts_at)
    end
  end
end
