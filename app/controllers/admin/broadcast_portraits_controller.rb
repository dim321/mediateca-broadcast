# frozen_string_literal: true

module Admin
  class BroadcastPortraitsController < Admin::BaseController
    before_action :set_portrait, only: %i[show edit update destroy]
    before_action :set_block_options, only: %i[new create edit update]

    def index
      @q = BroadcastPortrait.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @broadcast_portraits = @q.result.includes(:screen).page(params[:page]).per(25)
    end

    def show
    end

    def new
      @portrait = BroadcastPortrait.new(
        kind: "cyclic",
        block_frequencies_per_hour: [ 4 ],
        max_commercial_in_row: 3,
        neutral_min_seconds: 10
      )
    end

    def create
      @portrait = BroadcastPortrait.new(portrait_header_params)
      @portrait.screen_id = nil
      @portrait.kind = "cyclic"

      if timed_kind_requested?
        @portrait.errors.add(:kind, :inclusion)
        return render :new, status: :unprocessable_content
      end

      if @portrait.save
        return unless persist_blocks_or_render(:new)

        redirect_to admin_broadcast_portrait_path(@portrait), notice: t("admin.crud.created"), status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if timed_kind_requested?
        @portrait.errors.add(:kind, :inclusion)
        return render :edit, status: :unprocessable_content
      end

      if @portrait.update(portrait_header_params)
        return unless persist_blocks_or_enqueue_or_render

        redirect_to admin_broadcast_portrait_path(@portrait), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      destroy_with_restriction(@portrait, admin_broadcast_portraits_path, notice: t("admin.crud.destroyed"))
    end

    private

    def set_portrait
      @portrait = BroadcastPortrait.includes(:screen, blocks: [ :rotation, :service_theme ]).find(params[:id])
    end

    def set_block_options
      bound_ids = Array(@portrait&.blocks).filter_map(&:rotation_id)
      @rotations = Rotation.assignable(bound_ids).order(:name)
      @service_themes = ServiceTheme.order(:name)
    end

    def timed_kind_requested?
      params.dig(:broadcast_portrait, :kind).to_s == "timed"
    end

    def portrait_header_params
      permitted = params.require(:broadcast_portrait).permit(
        :name, :max_commercial_in_row, :neutral_min_seconds, :is_default,
        block_frequencies_per_hour: []
      )
      permitted[:block_frequencies_per_hour] = Array(permitted[:block_frequencies_per_hour]).map(&:to_i)
      permitted = permitted.except(:is_default) if @portrait&.screen_id.present?
      permitted
    end

    def blocks_submitted?
      params[:broadcast_portrait].is_a?(ActionController::Parameters) &&
        params[:broadcast_portrait].key?(:blocks)
    end

    def block_payloads
      raw = params.dig(:broadcast_portrait, :blocks)
      return [] if raw.blank?
      return raw.values if raw.is_a?(ActionController::Parameters) && !raw.key?(:kind)

      Array(raw)
    end

    def normalized_blocks
      block_payloads.filter_map do |block|
        next if block.blank?

        attrs = if block.respond_to?(:permit)
          block.permit(:position, :kind, :rotation_id, :pick_strategy, :time_of_day, :service_theme_id).to_h
        else
          block.to_h.slice("position", "kind", "rotation_id", "pick_strategy", "time_of_day", "service_theme_id",
            :position, :kind, :rotation_id, :pick_strategy, :time_of_day, :service_theme_id)
        end
        attrs = attrs.with_indifferent_access
        %w[rotation_id pick_strategy time_of_day service_theme_id].each do |key|
          attrs[key] = nil if attrs[key].blank?
        end
        next if attrs[:kind].blank?

        attrs
      end
    end

    def persist_blocks_or_render(view)
      upsert_submitted_blocks!
      true
    rescue ActiveRecord::RecordInvalid => e
      @portrait.blocks.reload if @portrait.persisted?
      @portrait.errors.add(:base, e.message)
      render view, status: :unprocessable_content
      false
    end

    def persist_blocks_or_enqueue_or_render
      if blocks_submitted?
        persist_blocks_or_render(:edit)
      else
        Playlists::EnqueueRegen.from_screen(@portrait.screen) if @portrait.screen
        true
      end
    end

    def upsert_submitted_blocks!
      return unless blocks_submitted?

      Portraits::UpsertBlocks.call(portrait: @portrait, blocks: normalized_blocks)
    end
  end
end
