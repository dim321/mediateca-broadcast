# frozen_string_literal: true

module Admin
  class PlayLogsController < Admin::BaseController
    def index
      @q = PlayLog.ransack(ransack_params)
      @q.sorts = "started_at desc" if @q.sorts.empty?
      @play_logs = @q.result.includes(:organization, :screen, :media_asset).page(params[:page]).per(25)
    end

    def show
      @play_log = PlayLog.find(params[:id])
    end

    def new
      @play_log = PlayLog.new(started_at: Time.current)
    end

    def create
      @play_log = PlayLog.new(play_log_params)
      if @play_log.save
        redirect_to admin_play_log_path(@play_log), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @play_log = PlayLog.find(params[:id])
    end

    def update
      @play_log = PlayLog.find(params[:id])
      if @play_log.update(play_log_params)
        redirect_to admin_play_log_path(@play_log), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @play_log = PlayLog.find(params[:id])
      @play_log.destroy!
      redirect_to admin_play_logs_path, notice: t("admin.crud.destroyed"), status: :see_other
    end

    private

    def play_log_params
      params.expect(play_log: [ :organization_id, :screen_id, :media_asset_id, :source, :started_at ])
    end
  end
end
