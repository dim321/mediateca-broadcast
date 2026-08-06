# frozen_string_literal: true

class MediaPlansController < ApplicationController
  before_action :require_user
  before_action :set_media_plan, only: %i[show edit update cancel reschedule]
  before_action :load_form_collections, only: %i[new create edit update reschedule]

  def index
    authorize MediaPlan
    @media_plans = policy_scope(MediaPlan)
      .active
      .includes(:rotation, :broadcast_point_group, :airtime_booking)
      .order(starts_at: :desc)
  end

  def show
    authorize @media_plan
  end

  def new
    @media_plan = policy_scope(MediaPlan).new(organization: Current.user.organization)
    authorize @media_plan
    load_occupancy
  end

  def create
    @media_plan = policy_scope(MediaPlan).new(organization: Current.user.organization)
    authorize @media_plan

    group = rotation = starts_at = ends_at = nil
    group, rotation, starts_at, ends_at = resolve_slot_inputs
    return render_new_failure if @media_plan.errors.any?

    Airtime::OccupyWithPlan.call(
      organization: Current.user.organization,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: starts_at,
      ends_at: ends_at
    )
    redirect_to media_plans_path, notice: t('.created')
  rescue Airtime::ConflictError, Airtime::InvalidWindowError, ArgumentError, ActiveRecord::RecordInvalid => e
    attach_slot_attrs(group, rotation, starts_at, ends_at)
    flash.now[:alert] = e.message
    render_new_failure
  end

  def edit
    authorize @media_plan
  end

  def update
    authorize @media_plan
    rotation = policy_scope(Rotation).find_by(id: media_plan_params[:rotation_id])
    unless rotation
      @media_plan.errors.add(:rotation, :blank)
      return render :edit, status: :unprocessable_content
    end

    if window_or_group_change_attempted?
      @media_plan.errors.add(:base, :use_reschedule)
      return render :edit, status: :unprocessable_content
    end

    @media_plan.rotation = rotation
    if @media_plan.save
      redirect_to media_plans_path, notice: t('.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  def cancel
    authorize @media_plan, :cancel?
    Airtime::Cancel.call(plan: @media_plan)
    redirect_to media_plans_path, notice: t('.cancelled')
  rescue ArgumentError => e
    redirect_to media_plan_path(@media_plan), alert: e.message
  end

  def reschedule
    authorize @media_plan, :reschedule?

    if request.get?
      load_occupancy(exclude: @media_plan.airtime_booking)
      return
    end

    group = starts_at = ends_at = nil
    group, _rotation, starts_at, ends_at = resolve_slot_inputs(require_rotation: false)
    if @media_plan.errors.any?
      load_occupancy(exclude: @media_plan.airtime_booking)
      return render :reschedule, status: :unprocessable_content
    end

    Airtime::Reschedule.call(
      plan: @media_plan,
      broadcast_point_group: group,
      starts_at: starts_at,
      ends_at: ends_at
    )
    redirect_to media_plans_path, notice: t('.rescheduled')
  rescue Airtime::ConflictError, Airtime::InvalidWindowError, ArgumentError => e
    flash.now[:alert] = e.message
    attach_slot_attrs(group, @media_plan.rotation, starts_at, ends_at)
    load_form_collections
    load_occupancy(exclude: @media_plan.airtime_booking)
    render :reschedule, status: :unprocessable_content
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t('media_assets.authentication_required')
  end

  def set_media_plan
    @media_plan = policy_scope(MediaPlan).find(params[:id])
  end

  def load_form_collections
    @rotations = policy_scope(Rotation).order(:name)
    @broadcast_point_groups = policy_scope(BroadcastPointGroup).order(:name)
  end

  def load_occupancy(exclude: nil)
    group_id = media_plan_params[:broadcast_point_group_id].presence ||
      @media_plan&.broadcast_point_group_id
    group = @broadcast_point_groups&.detect { |g| g.id == group_id.to_i } ||
      policy_scope(BroadcastPointGroup).find_by(id: group_id)
    @occupied_slots = if group
      Airtime::OccupancyPresenter.call(
        broadcast_point_group: group,
        exclude_booking: exclude
      )
    else
      []
    end
  end

  def resolve_slot_inputs(require_rotation: true)
    group = policy_scope(BroadcastPointGroup).find_by(id: media_plan_params[:broadcast_point_group_id])
    rotation = if require_rotation
      policy_scope(Rotation).find_by(id: media_plan_params[:rotation_id])
    else
      @media_plan.rotation
    end

    @media_plan.errors.add(:broadcast_point_group, :blank) unless group
    @media_plan.errors.add(:rotation, :blank) if require_rotation && rotation.blank?

    starts_at = nil
    ends_at = nil
    if media_plan_params[:starts_at].blank? || media_plan_params[:ends_at].blank?
      @media_plan.errors.add(:starts_at, :blank)
    else
      begins, ends = Scheduling::TimeWindowResolver.utc_range(
        organization: Current.user.organization,
        starts_at_param: media_plan_params[:starts_at],
        ends_at_param: media_plan_params[:ends_at]
      )
      starts_at = begins
      ends_at = ends
    end

    [ group, rotation, starts_at, ends_at ]
  rescue ArgumentError, TypeError
    @media_plan.errors.add(:starts_at, :invalid)
    [ group, rotation, nil, nil ]
  end

  def attach_slot_attrs(group, rotation, starts_at, ends_at)
    @media_plan.broadcast_point_group = group if group
    @media_plan.rotation = rotation if rotation
    @media_plan.starts_at = starts_at if starts_at
    @media_plan.ends_at = ends_at if ends_at
  end

  def render_new_failure
    load_form_collections
    load_occupancy
    render :new, status: :unprocessable_content
  end

  def window_or_group_change_attempted?
    params_group = media_plan_params[:broadcast_point_group_id]
    params_starts = media_plan_params[:starts_at]
    params_ends = media_plan_params[:ends_at]
    return true if params_group.present? && params_group.to_i != @media_plan.broadcast_point_group_id
    return false if params_starts.blank? && params_ends.blank?

    if params_starts.present? && params_ends.present?
      starts_at, ends_at = Scheduling::TimeWindowResolver.utc_range(
        organization: Current.user.organization,
        starts_at_param: params_starts,
        ends_at_param: params_ends
      )
      return starts_at != @media_plan.starts_at || ends_at != @media_plan.ends_at
    end

    params_starts.present? || params_ends.present?
  rescue ArgumentError, TypeError
    true
  end

  def media_plan_params
    params.fetch(:media_plan, {}).permit(
      :rotation_id,
      :broadcast_point_group_id,
      :starts_at,
      :ends_at
    )
  end
end
