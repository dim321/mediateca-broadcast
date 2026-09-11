# frozen_string_literal: true

module Admin
  class RotationItemsController < Admin::BaseController
    before_action :set_rotation_item, only: %i[show edit update destroy]
    before_action :set_assignable_rotations, only: %i[new create edit update]

    def index
      @q = RotationItem.ransack(ransack_params)
      @q.sorts = "id desc" if @q.sorts.empty?
      @rotation_items = @q.result.includes(:rotation, :media_asset).page(params[:page]).per(25)
    end

    def show
    end

    def new
      @rotation_item = RotationItem.new
    end

    def create
      @rotation_item = RotationItem.new(rotation_item_params)
      if @rotation_item.save
        Playlists::EnqueueRegen.from_rotation(@rotation_item.rotation)
        redirect_to admin_rotation_item_path(@rotation_item), notice: t("admin.crud.created"), status: :see_other
      else
        set_assignable_rotations
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      previous_rotation = @rotation_item.rotation
      if @rotation_item.update(rotation_item_params)
        Playlists::EnqueueRegen.from_rotation(@rotation_item.rotation)
        if previous_rotation && previous_rotation.id != @rotation_item.rotation_id
          Playlists::EnqueueRegen.from_rotation(previous_rotation)
        end
        redirect_to admin_rotation_item_path(@rotation_item), notice: t("admin.crud.updated"), status: :see_other
      else
        set_assignable_rotations
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      rotation = @rotation_item.rotation
      @rotation_item.destroy!
      Playlists::EnqueueRegen.from_rotation(rotation)
      redirect_to admin_rotation_items_path, notice: t("admin.crud.destroyed"), status: :see_other
    end

    private

    def set_rotation_item
      @rotation_item = RotationItem.find(params[:id])
    end

    def set_assignable_rotations
      extra = @rotation_item&.rotation_id || params.dig(:rotation_item, :rotation_id)
      @rotations = Rotation.assignable(extra).order(:name)
    end

    def rotation_item_params
      params.expect(rotation_item: [ :rotation_id, :media_asset_id, :position, :display_duration_seconds ])
    end
  end
end
