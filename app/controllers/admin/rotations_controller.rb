# frozen_string_literal: true

module Admin
  class RotationsController < Admin::BaseController
    def index
      @q = Rotation.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @rotations = @q.result.includes(:organization).page(params[:page]).per(25)
    end

    def show
      @rotation = Rotation.find(params[:id])
    end

    def new
      @rotation = Rotation.new
    end

    def create
      @rotation = Rotation.new(rotation_params)
      if @rotation.save
        redirect_to admin_rotation_path(@rotation), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @rotation = Rotation.find(params[:id])
    end

    def update
      @rotation = Rotation.find(params[:id])
      if @rotation.update(rotation_params)
        redirect_to admin_rotation_path(@rotation), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @rotation = Rotation.find(params[:id])
      destroy_with_restriction(@rotation, admin_rotations_path, notice: t("admin.crud.destroyed"))
    end

    private

    def rotation_params
      params.expect(rotation: [ :organization_id, :name, :system_managed ])
    end
  end
end
