# frozen_string_literal: true

class MediaPlansController < ApplicationController
  before_action :require_user
  before_action :set_media_plan, only: %i[show edit update destroy]
  before_action :load_form_collections, only: %i[new create edit update]

  def index
    authorize MediaPlan
    @media_plans = policy_scope(MediaPlan)
      .includes(:rotation, :broadcast_point_group)
      .order(starts_at: :desc)
  end

  def show
    authorize @media_plan
  end

  def new
    @media_plan = policy_scope(MediaPlan).new(organization: Current.user.organization)
    authorize @media_plan
  end

  def create
    @media_plan = policy_scope(MediaPlan).new(organization: Current.user.organization)
    authorize @media_plan
    assign_media_plan_attributes(@media_plan)
    if @media_plan.save
      redirect_to media_plans_path, notice: t(".created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @media_plan
  end

  def update
    authorize @media_plan
    assign_media_plan_attributes(@media_plan)
    if @media_plan.save
      redirect_to media_plans_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @media_plan
    @media_plan.destroy!
    redirect_to media_plans_path, notice: t(".destroyed")
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_media_plan
    @media_plan = policy_scope(MediaPlan).find(params[:id])
  end

  def load_form_collections
    @rotations = policy_scope(Rotation).order(:name)
    @broadcast_point_groups = policy_scope(BroadcastPointGroup).order(:name)
  end

  def assign_media_plan_attributes(media_plan)
    media_plan.rotation = policy_scope(Rotation).find_by(id: media_plan_params[:rotation_id])
    media_plan.broadcast_point_group = policy_scope(BroadcastPointGroup).find_by(id: media_plan_params[:broadcast_point_group_id])
    apply_parsed_times(media_plan)
  end

  def apply_parsed_times(media_plan)
    starts_at = media_plan_params[:starts_at]
    ends_at = media_plan_params[:ends_at]
    if starts_at.blank? || ends_at.blank?
      media_plan.errors.add(:starts_at, :blank)
      return
    end

    media_plan.starts_at, media_plan.ends_at = Scheduling::TimeWindowResolver.utc_range(
      organization: Current.user.organization,
      starts_at_param: starts_at,
      ends_at_param: ends_at
    )
  rescue ArgumentError, TypeError
    media_plan.errors.add(:starts_at, :invalid)
  end

  def media_plan_params
    params.require(:media_plan).permit(:rotation_id, :broadcast_point_group_id, :starts_at, :ends_at)
  end
end
