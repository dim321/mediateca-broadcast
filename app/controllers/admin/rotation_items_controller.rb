# frozen_string_literal: true

module Admin
  class RotationItemsController < Admin::BaseController
    def index
      @q = RotationItem.ransack(ransack_params)
      @q.sorts = "id desc" if @q.sorts.empty?
      @rotation_items = @q.result.includes(:rotation, :media_asset).page(params[:page]).per(25)
    end

    def show
      @rotation_item = RotationItem.find(params[:id])
    end

    def new
      @rotation_item = RotationItem.new
    end

    def create
      @rotation_item = RotationItem.new(rotation_item_params)
      if @rotation_item.save
        redirect_to admin_rotation_item_path(@rotation_item), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @rotation_item = RotationItem.find(params[:id])
    end

    def update
      @rotation_item = RotationItem.find(params[:id])
      if @rotation_item.update(rotation_item_params)
        redirect_to admin_rotation_item_path(@rotation_item), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @rotation_item = RotationItem.find(params[:id])
      @rotation_item.destroy!
      redirect_to admin_rotation_items_path, notice: t("admin.crud.destroyed"), status: :see_other
    end

    private

    def rotation_item_params
      params.expect(rotation_item: [ :rotation_id, :media_asset_id, :position, :display_duration_seconds ])
    end
  end
end
