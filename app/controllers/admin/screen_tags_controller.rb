# frozen_string_literal: true

module Admin
  class ScreenTagsController < Admin::BaseController
    def index
      @q = ScreenTag.ransack(ransack_params)
      @q.sorts = "id desc" if @q.sorts.empty?
      @screen_tags = @q.result.includes(:screen, :tag).page(params[:page]).per(25)
    end

    def show
      @screen_tag = ScreenTag.find(params[:id])
    end

    def new
      @screen_tag = ScreenTag.new
    end

    def create
      @screen_tag = ScreenTag.new(screen_tag_params)
      if @screen_tag.save
        redirect_to admin_screen_tag_path(@screen_tag), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @screen_tag = ScreenTag.find(params[:id])
    end

    def update
      @screen_tag = ScreenTag.find(params[:id])
      if @screen_tag.update(screen_tag_params)
        redirect_to admin_screen_tag_path(@screen_tag), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @screen_tag = ScreenTag.find(params[:id])
      @screen_tag.destroy!
      redirect_to admin_screen_tags_path, notice: t("admin.crud.destroyed"), status: :see_other
    end

    private

    def screen_tag_params
      params.expect(screen_tag: [ :screen_id, :tag_id ])
    end
  end
end
