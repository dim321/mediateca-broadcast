# frozen_string_literal: true

class BroadcastPointGroupsController < ApplicationController
  before_action :require_user
  before_action :set_broadcast_point_group, only: %i[show edit update add_screens remove_member]

  def index
    authorize BroadcastPointGroup
    @broadcast_point_groups = policy_scope(BroadcastPointGroup).order(:name)
  end

  def show
    authorize @broadcast_point_group
    @members = @broadcast_point_group.screens.includes(:organization, :station).order(:name)
    @available_screens = Screen.where.not(id: @members.select(:id)).includes(:organization, :station).order(:name)
  end

  def new
    @broadcast_point_group = policy_scope(BroadcastPointGroup).new(organization: Current.user.organization)
    authorize @broadcast_point_group
  end

  def create
    @broadcast_point_group = policy_scope(BroadcastPointGroup).new(broadcast_point_group_params)
    @broadcast_point_group.organization = Current.user.organization
    authorize @broadcast_point_group
    if @broadcast_point_group.save
      redirect_to @broadcast_point_group, notice: t(".created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @broadcast_point_group
  end

  def update
    authorize @broadcast_point_group
    if @broadcast_point_group.update(broadcast_point_group_params)
      redirect_to @broadcast_point_group, notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def add_screens
    authorize @broadcast_point_group, :add_screens?
    screen_ids = Array(params[:screen_ids]).compact_blank.map(&:to_i).uniq
    screens = Screen.where(id: screen_ids)
    @broadcast_point_group.screens << screens
    redirect_to @broadcast_point_group, notice: t(".screens_added", count: screens.size)
  rescue ActiveRecord::RecordNotUnique
    redirect_to @broadcast_point_group, alert: t(".screens_not_added")
  end

  def remove_member
    authorize @broadcast_point_group, :remove_member?
    membership = @broadcast_point_group.broadcast_point_group_memberships.find_by!(screen_id: params[:screen_id])
    membership.destroy!
    redirect_to @broadcast_point_group, notice: t(".member_removed")
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_broadcast_point_group
    @broadcast_point_group = policy_scope(BroadcastPointGroup).find(params[:id])
  end

  def broadcast_point_group_params
    params.require(:broadcast_point_group).permit(:name)
  end
end
