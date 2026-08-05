# frozen_string_literal: true

class AirtimeBookingsController < ApplicationController
  before_action :require_user
  before_action :set_booking, only: %i[show cancel reschedule]
  before_action :load_form_collections, only: %i[new create reschedule]

  def index
    authorize AirtimeBooking
    @airtime_bookings = policy_scope(AirtimeBooking)
      .includes(:broadcast_point_group, :airtime_quota)
      .order(starts_at: :desc)
  end

  def show
    authorize @airtime_booking
    @occupied_slots = Airtime::OccupancyPresenter.call(
      broadcast_point_group: @airtime_booking.broadcast_point_group,
      exclude_booking: @airtime_booking
    )
  end

  def new
    authorize AirtimeBooking
    @airtime_booking = AirtimeBooking.new
    load_occupancy_for_selected_quota
  end

  def create
    authorize AirtimeBooking
    quota = policy_scope(AirtimeQuota).find_by(id: booking_params[:airtime_quota_id])
    starts_at = nil
    ends_at = nil

    unless quota
      @airtime_booking = AirtimeBooking.new
      flash.now[:alert] = t('.quota_not_found')
      load_occupancy_for_selected_quota
      return render :new, status: :unprocessable_content
    end

    starts_at, ends_at = parse_times
    booking = Airtime::Book.call(
      quota: quota,
      organization: Current.user.organization,
      starts_at: starts_at,
      ends_at: ends_at
    )
    redirect_to airtime_booking_path(booking), notice: t('.created')
  rescue Airtime::OverflowError, Airtime::ConflictError, Airtime::InvalidWindowError, ArgumentError => e
    @airtime_booking = AirtimeBooking.new(airtime_quota: quota, starts_at: starts_at, ends_at: ends_at)
    flash.now[:alert] = e.message
    load_form_collections
    load_occupancy_for_selected_quota
    render :new, status: :unprocessable_content
  end

  def cancel
    authorize @airtime_booking, :cancel?
    Airtime::Cancel.call(booking: @airtime_booking)
    redirect_to airtime_bookings_path, notice: t('.cancelled')
  rescue Airtime::CancelBlockedError => e
    redirect_to airtime_booking_path(@airtime_booking), alert: e.message
  end

  def reschedule
    authorize @airtime_booking, :reschedule?

    if request.get?
      load_occupancy_for_selected_quota(exclude: @airtime_booking)
      return
    end

    quota = policy_scope(AirtimeQuota).find_by(id: booking_params[:airtime_quota_id])
    raise ArgumentError, 'quota not found' unless quota

    starts_at, ends_at = parse_times
    Airtime::Reschedule.call(
      booking: @airtime_booking,
      quota: quota,
      starts_at: starts_at,
      ends_at: ends_at
    )
    redirect_to airtime_booking_path(@airtime_booking), notice: t('.rescheduled')
  rescue Airtime::OverflowError, Airtime::ConflictError, Airtime::InvalidWindowError, ArgumentError => e
    flash.now[:alert] = e.message
    load_form_collections
    load_occupancy_for_selected_quota(exclude: @airtime_booking)
    render :reschedule, status: :unprocessable_content
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t('media_assets.authentication_required')
  end

  def set_booking
    @airtime_booking = policy_scope(AirtimeBooking).find(params[:id])
  end

  def load_form_collections
    @quotas = policy_scope(AirtimeQuota).includes(:broadcast_point_group).order(:starts_at)
  end

  def booking_params
    params.fetch(:airtime_booking, {}).permit(:airtime_quota_id, :starts_at, :ends_at)
  end

  def parse_times
    starts_at = booking_params[:starts_at]
    ends_at = booking_params[:ends_at]
    raise Airtime::InvalidWindowError, 'starts_at and ends_at required' if starts_at.blank? || ends_at.blank?

    Scheduling::TimeWindowResolver.utc_range(
      organization: Current.user.organization,
      starts_at_param: starts_at,
      ends_at_param: ends_at
    )
  rescue ArgumentError, TypeError
    raise Airtime::InvalidWindowError, 'invalid time window'
  end

  def load_occupancy_for_selected_quota(exclude: nil)
    quota_id = booking_params[:airtime_quota_id].presence || @airtime_booking&.airtime_quota_id
    quota = @quotas&.detect { |q| q.id == quota_id.to_i } || policy_scope(AirtimeQuota).find_by(id: quota_id)
    @selected_quota = quota
    @occupied_slots = if quota
      Airtime::OccupancyPresenter.call(
        broadcast_point_group: quota.broadcast_point_group,
        exclude_booking: exclude
      )
    else
      []
    end
  end
end
