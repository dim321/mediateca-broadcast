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
    @members = @broadcast_point_group.screens.includes(:station).order(:name)
    @catalog_tags = policy_scope(Tag).order(:name)
    @selected_tag_ids = Array(params[:tag_ids]).map(&:to_i).uniq.reject(&:zero?)
    @available_screens = available_catalog_screens.includes(:station, :tags).order(:name)
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
    screens = catalog_screens.where(id: screen_ids)

    if screens.size != screen_ids.size
      redirect_to @broadcast_point_group, alert: t(".screens_not_in_catalog")
      return
    end

    ActiveRecord::Base.transaction do
      screens.each do |screen|
        @broadcast_point_group.broadcast_point_group_memberships.create!(screen:)
      end
    end
    redirect_to @broadcast_point_group, notice: t(".screens_added", count: screens.size)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
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

  def catalog_screens
    Screen.operator_catalog
  end

  def available_catalog_screens
    Fleet::FilterScreens.call(
      scope: catalog_screens.where.not(id: @members.select(:id)),
      tag_ids: @selected_tag_ids
    )
  end
end
