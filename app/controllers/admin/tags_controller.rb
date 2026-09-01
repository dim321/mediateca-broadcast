# frozen_string_literal: true

module Admin
  class TagsController < Admin::BaseController
    def index
      @q = Tag.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @tags = @q.result.page(params[:page]).per(25)
    end

    def show
      @tag = Tag.find(params[:id])
    end

    def new
      @tag = Tag.new
    end

    def create
      @tag = Tag.new(tag_params)
      if @tag.save
        redirect_to admin_tag_path(@tag), notice: t("admin.tags.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @tag = Tag.find(params[:id])
    end

    def update
      @tag = Tag.find(params[:id])
      if @tag.update(tag_params)
        redirect_to admin_tag_path(@tag), notice: t("admin.tags.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @tag = Tag.find(params[:id])
      @tag.destroy!
      redirect_to admin_tags_path, notice: t("admin.tags.destroyed"), status: :see_other
    end

    private

    def tag_params
      params.expect(tag: [ :name ])
    end
  end
end
