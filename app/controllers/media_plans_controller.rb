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

    plan = Airtime::OccupyWithPlan.call(
      organization: Current.user.organization,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: starts_at,
      ends_at: ends_at,
      placement_kind: media_plan_params[:placement_kind].presence || :own_atmosphere,
      shows_per_hour: media_plan_params[:shows_per_hour].presence
    )
    flash_commercial_quota_warning(plan)
    redirect_to media_plans_path, notice: t(".created")
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
    rotation = find_scoped_rotation
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
      redirect_to media_plans_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def cancel
    authorize @media_plan, :cancel?
    Airtime::Cancel.call(plan: @media_plan)
    redirect_to media_plans_path, notice: t(".cancelled")
  rescue ArgumentError => e
    redirect_to media_plan_path(@media_plan), alert: e.message
  end

  def reschedule
    authorize @media_plan, :reschedule?

    if request.get? || request.head?
      load_occupancy(exclude: @media_plan.airtime_booking)
      return
    end

    group = starts_at = ends_at = nil
    group, _rotation, starts_at, ends_at = resolve_slot_inputs(require_rotation: false)
    return render_reschedule_failure if @media_plan.errors.any?

    Airtime::Reschedule.call(
      plan: @media_plan,
      broadcast_point_group: group,
      starts_at: starts_at,
      ends_at: ends_at
    )
    flash_commercial_quota_warning(@media_plan.reload)
    redirect_to media_plans_path, notice: t(".rescheduled")
  rescue Airtime::ConflictError, Airtime::InvalidWindowError, ArgumentError => e
    flash.now[:alert] = e.message
    render_reschedule_failure(group: group, starts_at: starts_at, ends_at: ends_at)
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_media_plan
    @media_plan = policy_scope(MediaPlan).includes(:airtime_booking).find(params[:id])
  end

  def load_form_collections
    @rotations = policy_scope(Rotation).unmanaged.order(:name)
    own_groups = policy_scope(BroadcastPointGroup).to_a
    owner_groups = BroadcastPointGroup.commercial_eligible_groups_for(Current.user.organization).to_a
    @broadcast_point_groups = (own_groups + owner_groups).uniq.sort_by(&:name)
  end

  def find_placement_group
    id = media_plan_params[:broadcast_point_group_id]
    policy_scope(BroadcastPointGroup).find_by(id: id) ||
      BroadcastPointGroup.commercial_eligible_groups_for(Current.user.organization).find_by(id: id)
  end

  def flash_commercial_quota_warning(plan)
    result = CommercialQuota::Check.call(plan: plan)
    return unless result.exceeded

    flash[:warning] = t("media_plans.commercial_quota_exceeded")
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
    group = find_placement_group
    rotation = if require_rotation
      find_scoped_rotation
    else
      @media_plan.rotation
    end

    @media_plan.errors.add(:broadcast_point_group, :blank) unless group
    @media_plan.errors.add(:rotation, :blank) if require_rotation && rotation.blank?

    starts_at = nil
    ends_at = nil
    case parse_slot_window
    in :blank
      @media_plan.errors.add(:starts_at, :blank)
    in :invalid
      @media_plan.errors.add(:starts_at, :invalid)
    in [ begins, ends ]
      starts_at = begins
      ends_at = ends
    end

    attach_placement_attrs
    [ group, rotation, starts_at, ends_at ]
  end

  def attach_placement_attrs
    kind = media_plan_params[:placement_kind]
    @media_plan.placement_kind = kind if kind.present?
    return unless media_plan_params.key?(:shows_per_hour)

    @media_plan.shows_per_hour = media_plan_params[:shows_per_hour].presence
  end

  def parse_slot_window
    starts_param = media_plan_params[:starts_at]
    ends_param = media_plan_params[:ends_at]
    return :blank if starts_param.blank? || ends_param.blank?

    Scheduling::TimeWindowResolver.utc_range(
      organization: Current.user.organization,
      starts_at_param: starts_param,
      ends_at_param: ends_param
    )
  rescue ArgumentError, TypeError
    :invalid
  end

  def find_scoped_rotation
    policy_scope(Rotation).find_by(id: media_plan_params[:rotation_id])
  end

  def attach_slot_attrs(group, rotation, starts_at, ends_at)
    @media_plan.broadcast_point_group = group if group
    @media_plan.rotation = rotation if rotation
    @media_plan.starts_at = starts_at if starts_at
    @media_plan.ends_at = ends_at if ends_at
  end

  def render_new_failure
    load_occupancy
    render :new, status: :unprocessable_content
  end

  def render_reschedule_failure(group: nil, starts_at: nil, ends_at: nil)
    attach_slot_attrs(group, @media_plan.rotation, starts_at, ends_at)
    load_occupancy(exclude: @media_plan.airtime_booking)
    render :reschedule, status: :unprocessable_content
  end

  def window_or_group_change_attempted?
    params_group = media_plan_params[:broadcast_point_group_id]
    return true if params_group.present? && params_group.to_i != @media_plan.broadcast_point_group_id

    params_starts = media_plan_params[:starts_at]
    params_ends = media_plan_params[:ends_at]
    return false if params_starts.blank? && params_ends.blank?

    case parse_slot_window
    in [ starts_at, ends_at ]
      starts_at != @media_plan.starts_at || ends_at != @media_plan.ends_at
    else
      true
    end
  end

  def media_plan_params
    @media_plan_params ||= params.fetch(:media_plan, {}).permit(
      :rotation_id,
      :broadcast_point_group_id,
      :starts_at,
      :ends_at,
      :placement_kind,
      :shows_per_hour
    )
  end
end
