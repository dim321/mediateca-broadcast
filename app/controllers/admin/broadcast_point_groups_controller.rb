# frozen_string_literal: true

module Admin
  class BroadcastPointGroupsController < Admin::BaseController
    def index
      @q = BroadcastPointGroup.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @broadcast_point_groups = @q.result.includes(:organization).page(params[:page]).per(25)
    end

    def show
      @broadcast_point_group = BroadcastPointGroup.includes(:screens).find(params[:id])
    end

    def new
      @broadcast_point_group = BroadcastPointGroup.new
    end

    def create
      @broadcast_point_group = BroadcastPointGroup.new(broadcast_point_group_params)
      if @broadcast_point_group.save
        redirect_to admin_broadcast_point_group_path(@broadcast_point_group),
          notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @broadcast_point_group = BroadcastPointGroup.find(params[:id])
    end

    def update
      @broadcast_point_group = BroadcastPointGroup.find(params[:id])
      if @broadcast_point_group.update(broadcast_point_group_params)
        redirect_to admin_broadcast_point_group_path(@broadcast_point_group),
          notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @broadcast_point_group = BroadcastPointGroup.find(params[:id])
      destroy_with_restriction(
        @broadcast_point_group,
        admin_broadcast_point_groups_path,
        notice: t("admin.crud.destroyed")
      )
    end

    private

    def broadcast_point_group_params
      params.require(:broadcast_point_group).permit(
        :organization_id,
        :name,
        :commercial_quota_percent,
        :commercial_quota_period,
        screen_ids: []
      )
    end
  end
end
