# frozen_string_literal: true

class PointGroupsController < ApplicationController
  before_action :require_user
  before_action :set_point_group, only: %i[show edit update add_points remove_member]

  def index
    authorize PointGroup
    @point_groups = policy_scope(PointGroup).order(:name)
  end

  def show
    authorize @point_group
    @members = @point_group.broadcast_points.order(:name)
    member_ids = @members.pluck(:id)
    @available_points = policy_scope(BroadcastPoint).order(:name).where.not(id: member_ids)
  end

  def new
    @point_group = PointGroup.new(organization: Current.user.organization)
    authorize @point_group
  end

  def create
    @point_group = PointGroup.new(point_group_params)
    @point_group.organization = Current.user.organization
    authorize @point_group
    if @point_group.save
      redirect_to @point_group, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @point_group
  end

  def update
    authorize @point_group
    if @point_group.update(point_group_params)
      redirect_to @point_group, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def add_points
    authorize @point_group, :add_points?
    ids = Array(params[:broadcast_point_ids]).map(&:to_i).reject(&:zero?)
    manager = Fleet::GroupMembershipManager.new(point_group: @point_group)
    errors = 0
    policy_scope(BroadcastPoint).where(id: ids).find_each do |point|
      next if @point_group.broadcast_point_ids.include?(point.id)

      manager.add(point)
    rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      errors += 1
    end
    if errors.positive?
      redirect_to @point_group, alert: t(".points_add_failed")
    else
      redirect_to @point_group, notice: t(".points_added")
    end
  end

  def remove_member
    authorize @point_group, :remove_member?
    point = policy_scope(BroadcastPoint).find(params[:broadcast_point_id])
    Fleet::GroupMembershipManager.new(point_group: @point_group).remove(point)
    redirect_to @point_group, notice: t(".member_removed")
  end

  private

  def set_point_group
    @point_group = policy_scope(PointGroup).find(params[:id])
  end

  def point_group_params
    params.require(:point_group).permit(:name)
  end

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end
end
