# frozen_string_literal: true

module Admin
  class MediaPlansController < Admin::ApplicationController
    def cancel
      plan = requested_resource
      Airtime::Cancel.call(plan: plan)
      redirect_to admin_media_plans_path, notice: 'Media plan cancelled.'
    rescue ArgumentError => e
      redirect_to admin_media_plan_path(plan), alert: e.message
    end

    def reschedule
      @media_plan = requested_resource

      if request.get?
        @broadcast_point_groups = BroadcastPointGroup.order(:name)
        render :reschedule
        return
      end

      group = BroadcastPointGroup.find(params.require(:broadcast_point_group_id))
      starts_at = Time.zone.parse(params.require(:starts_at))
      ends_at = Time.zone.parse(params.require(:ends_at))

      Airtime::Reschedule.call(
        plan: @media_plan,
        broadcast_point_group: group,
        starts_at: starts_at,
        ends_at: ends_at
      )
      redirect_to admin_media_plan_path(@media_plan), notice: 'Media plan rescheduled.'
    rescue Airtime::ConflictError, Airtime::InvalidWindowError, ArgumentError => e
      @broadcast_point_groups = BroadcastPointGroup.order(:name)
      flash.now[:alert] = e.message
      render :reschedule, status: :unprocessable_content
    end
  end
end
