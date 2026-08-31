# frozen_string_literal: true

module Admin
  class MediaPlansController < Admin::ApplicationController
    def cancel
      plan = requested_resource
      Airtime::Cancel.call(plan: plan)
      redirect_to admin_media_plans_path, notice: t("admin.media_plans.cancelled")
    rescue ArgumentError => e
      redirect_to admin_media_plan_path(plan), alert: e.message
    end

    def reschedule
      @media_plan = requested_resource

      if request.get? || request.head?
        load_broadcast_point_groups
        render :reschedule
        return
      end

      group = @media_plan.organization.broadcast_point_groups.find(params.require(:broadcast_point_group_id))
      starts_at, ends_at = Scheduling::TimeWindowResolver.utc_range(
        organization: @media_plan.organization,
        starts_at_param: params.require(:starts_at),
        ends_at_param: params.require(:ends_at)
      )

      Airtime::Reschedule.call(
        plan: @media_plan,
        broadcast_point_group: group,
        starts_at: starts_at,
        ends_at: ends_at
      )
      redirect_to admin_media_plan_path(@media_plan), notice: t("admin.media_plans.rescheduled")
    rescue Airtime::ConflictError, Airtime::InvalidWindowError, ArgumentError => e
      load_broadcast_point_groups
      flash.now[:alert] = e.message
      render :reschedule, status: :unprocessable_content
    end

    private

    def load_broadcast_point_groups
      @time_zone = @media_plan.organization.time_zone
      @broadcast_point_groups = @media_plan.organization.broadcast_point_groups.order(:name)
    end
  end
end
