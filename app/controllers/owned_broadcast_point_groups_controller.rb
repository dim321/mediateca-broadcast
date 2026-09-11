# frozen_string_literal: true

class OwnedBroadcastPointGroupsController < ApplicationController
  before_action :require_user
  before_action :set_group, only: %i[show edit update add_screens remove_member]

  def index
    authorize BroadcastPointGroup, policy_class: OwnedBroadcastPointGroupPolicy
    @broadcast_point_groups = policy_scope(
      BroadcastPointGroup,
      policy_scope_class: OwnedBroadcastPointGroupPolicy::Scope
    ).order(:name)
  end

  def show
    authorize @broadcast_point_group, policy_class: OwnedBroadcastPointGroupPolicy
    @members = @broadcast_point_group.screens.includes(:station).order(:name)
    @available_screens = owned_screens_scope.where.not(id: @members.select(:id)).includes(:station).order(:name)
  end

  def edit
    authorize @broadcast_point_group, policy_class: OwnedBroadcastPointGroupPolicy
  end

  def update
    authorize @broadcast_point_group, policy_class: OwnedBroadcastPointGroupPolicy
    if @broadcast_point_group.update(group_params)
      redirect_to owned_broadcast_point_group_path(@broadcast_point_group), notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def add_screens
    authorize @broadcast_point_group, :add_screens?, policy_class: OwnedBroadcastPointGroupPolicy
    screen_ids = Array(params[:screen_ids]).compact_blank.map(&:to_i).uniq
    screens = owned_screens_scope.where(id: screen_ids)

    if screens.size != screen_ids.size
      redirect_to owned_broadcast_point_group_path(@broadcast_point_group), alert: t(".screens_not_owned")
      return
    end

    ActiveRecord::Base.transaction do
      screens.each do |screen|
        @broadcast_point_group.broadcast_point_group_memberships.create!(screen:)
      end
    end
    redirect_to owned_broadcast_point_group_path(@broadcast_point_group), notice: t(".screens_added", count: screens.size)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to owned_broadcast_point_group_path(@broadcast_point_group), alert: t(".screens_not_added")
  end

  def remove_member
    authorize @broadcast_point_group, :remove_member?, policy_class: OwnedBroadcastPointGroupPolicy
    membership = @broadcast_point_group.broadcast_point_group_memberships.find_by!(screen_id: params[:screen_id])
    membership.destroy!
    redirect_to owned_broadcast_point_group_path(@broadcast_point_group), notice: t(".member_removed")
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_group
    @broadcast_point_group = policy_scope(
      BroadcastPointGroup,
      policy_scope_class: OwnedBroadcastPointGroupPolicy::Scope
    ).find(params[:id])
  end

  def group_params
    params.require(:broadcast_point_group).permit(
      :name,
      :commercial_quota_percent,
      :commercial_quota_period
    ).tap do |permitted|
      permitted[:commercial_quota_percent] = nil if permitted[:commercial_quota_percent].blank?
      permitted[:commercial_quota_period] = nil if permitted[:commercial_quota_period].blank?
    end
  end

  def owned_screens_scope
    Current.user.organization.owned_screens
  end
end
