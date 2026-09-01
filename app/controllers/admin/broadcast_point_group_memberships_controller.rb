# frozen_string_literal: true

module Admin
  class BroadcastPointGroupMembershipsController < Admin::BaseController
    def index
      @q = BroadcastPointGroupMembership.ransack(ransack_params)
      @q.sorts = "id desc" if @q.sorts.empty?
      @broadcast_point_group_memberships = @q.result.includes(:broadcast_point_group, :screen)
        .page(params[:page]).per(25)
    end

    def show
      @broadcast_point_group_membership = BroadcastPointGroupMembership.find(params[:id])
    end

    def new
      @broadcast_point_group_membership = BroadcastPointGroupMembership.new
    end

    def create
      @broadcast_point_group_membership = BroadcastPointGroupMembership.new(membership_params)
      if @broadcast_point_group_membership.save
        redirect_to admin_broadcast_point_group_membership_path(@broadcast_point_group_membership),
          notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @broadcast_point_group_membership = BroadcastPointGroupMembership.find(params[:id])
    end

    def update
      @broadcast_point_group_membership = BroadcastPointGroupMembership.find(params[:id])
      if @broadcast_point_group_membership.update(membership_params)
        redirect_to admin_broadcast_point_group_membership_path(@broadcast_point_group_membership),
          notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @broadcast_point_group_membership = BroadcastPointGroupMembership.find(params[:id])
      @broadcast_point_group_membership.destroy!
      redirect_to admin_broadcast_point_group_memberships_path, notice: t("admin.crud.destroyed"), status: :see_other
    end

    private

    def membership_params
      params.expect(broadcast_point_group_membership: [ :broadcast_point_group_id, :screen_id ])
    end
  end
end
