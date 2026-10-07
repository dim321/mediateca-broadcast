# frozen_string_literal: true

module Admin
  class AdvertisingOrdersController < Admin::BaseController
    include AdvertisingOrderGrid

    helper AdvertisingOrdersHelper
    helper_method :operator_order_editor?

    def index
      @q = AdvertisingOrder.ransack(ransack_params)
      @q.sorts = "created_at desc" if @q.sorts.empty?
      @advertising_orders = @q.result.includes(:organization, :created_by).page(params[:page]).per(25)
      @organizations = Organization.order(:name)
    end

    def show
      @advertising_order = find_order
    end

    def new
      @form_organization = selected_organization
      @advertising_order = AdvertisingOrder.new(
        organization: @form_organization,
        placement_kind: :commercial
      )
      prepare_form
    end

    def create
      @form_organization = selected_organization
      media_assets = find_media_assets
      if media_assets.empty?
        @advertising_order = AdvertisingOrder.new(organization: @form_organization)
        @advertising_order.errors.add(:media_asset, :blank)
        return render_form_failure(:new)
      end

      @advertising_order = Advertising::CreateOrder.call(
        organization: @form_organization,
        created_by: Current.user,
        media_assets: media_assets,
        product_name: order_params[:product_name],
        placement_kind: order_params[:placement_kind].presence || :own_atmosphere,
        shows_per_hour: order_header_shows_per_hour,
        distribution_strategy: order_params[:distribution_strategy].presence || :linear
      )
      persist_grid!(@advertising_order)
      redirect_to admin_advertising_order_path(@advertising_order),
        notice: t("advertising_orders.create.created", name: @advertising_order.product_name)
    rescue Advertising::InvalidGrid => e
      @advertising_order = e.order
      @form_organization = @advertising_order.organization
      render_form_failure(:edit)
    rescue Advertising::Error => e
      @advertising_order ||= AdvertisingOrder.new(organization: @form_organization)
      @advertising_order.errors.add(:media_asset, e.message)
      render_form_failure(:new)
    rescue ActiveRecord::RecordInvalid => e
      @advertising_order = e.record if e.record.is_a?(AdvertisingOrder)
      @advertising_order ||= AdvertisingOrder.new(organization: @form_organization)
      render_form_failure(:new)
    end

    def edit
      @advertising_order = find_order
      return if redirect_rejected_edit

      @form_organization = @advertising_order.organization
      prepare_form
    end

    def update
      @advertising_order = find_order
      @form_organization = @advertising_order.organization
      return if redirect_rejected_edit
      return update_active_order! if @advertising_order.active?

      resubmitting = @advertising_order.rejected?
      clip_media_assets = find_media_assets if clip_ids_submitted?
      AdvertisingOrder.transaction do
        @advertising_order.update!(header_update_attrs)
        if clip_media_assets
          Advertising::UpdateOrderClips.call(
            order: @advertising_order,
            media_assets: clip_media_assets,
            enqueue_regen: false
          )
        end
        persist_grid!(@advertising_order)
        Advertising::ResubmitOrder.call(order: @advertising_order) if resubmitting
      end
      Advertising::UpdateOrderClips.enqueue_regen_for(@advertising_order) if clip_media_assets && @advertising_order.active?
      notice = resubmitting ? "advertising_orders.update.resubmitted" : "advertising_orders.update.updated"
      redirect_to admin_advertising_order_path(@advertising_order), notice: t(notice)
    rescue Advertising::InvalidGrid => e
      @advertising_order = e.order
      @form_organization = @advertising_order.organization
      render_form_failure(:edit)
    rescue Advertising::Error => e
      @advertising_order.errors.add(:media_asset, e.message)
      render_form_failure(:edit)
    rescue ActiveRecord::RecordInvalid
      render_form_failure(:edit)
    end

    def activate
      order = find_order
      unless AdvertisingOrderPolicy.new(Current.user, order).activate?
        redirect_to admin_advertising_order_path(order), alert: t("pundit.not_authorized"), status: :see_other
        return
      end

      result = Advertising::ActivateOrder.call(order: order)
      flash[:notice] = t("advertising_orders.activate.activated")
      flash[:warning] = t("advertising_orders.activate.quota_exceeded") if result.quota_exceeded
      if result.conflicted_windows.any?
        flash[:alert] = t("advertising_orders.activate.conflicts", count: result.conflicted_windows.size)
      end
      redirect_to admin_advertising_order_path(order)
    rescue Advertising::Error => e
      redirect_to admin_advertising_order_path(find_order), alert: e.message
    end

    def reject
      order = find_order
      unless AdvertisingOrderPolicy.new(Current.user, order).reject?
        redirect_to admin_advertising_order_path(order), alert: t("pundit.not_authorized"), status: :see_other
        return
      end

      Advertising::RejectOrder.call(order: order, rejection_reason: params[:rejection_reason])
      redirect_to admin_advertising_order_path(order),
        notice: t("admin.advertising_orders.rejected"),
        status: :see_other
    rescue Advertising::Error => e
      redirect_to admin_advertising_order_path(order), alert: e.message, status: :see_other
    end

    def copy
      source = AdvertisingOrder.find(params[:id])
      order = Advertising::CopyOrder.call(source: source, created_by: Current.user)
      redirect_to edit_admin_advertising_order_path(order),
        notice: t("advertising_orders.copy.created"),
        status: :see_other
    rescue Advertising::Error => e
      redirect_to admin_advertising_orders_path, alert: e.message, status: :see_other
    end

    def cancel
      order = find_order
      Advertising::CancelOrder.call(order: order)
      redirect_to admin_advertising_order_path(order),
        notice: t("admin.advertising_orders.cancelled")
    rescue Advertising::Error => e
      redirect_to admin_advertising_order_path(order), alert: e.message, status: :see_other
    end

    private

    def operator_order_editor?
      Current.user.manager? || Current.user.administrator?
    end

    def redirect_rejected_edit
      return false unless @advertising_order.rejected? && !operator_order_editor?

      redirect_to admin_advertising_order_path(@advertising_order),
        alert: t("pundit.not_authorized"),
        status: :see_other
      true
    end

    def find_order
      AdvertisingOrder.includes(
        :organization,
        :created_by,
        :advertising_order_windows,
        { rotation: { rotation_items: { media_asset: { file_attachment: :blob } } } },
        advertising_order_lines: [ :screen, :advertising_order_line_days ],
        media_asset: [ { file_attachment: :blob } ]
      ).find(params[:id])
    end

    def selected_organization
      Organization.find_by(id: requested_organization_id) || Organization.order(:name).first
    end

    def requested_organization_id
      params[:organization_id].presence || order_params[:organization_id]
    end

    def load_form_collections
      @organizations = Organization.order(:name)
      @grid_dates = grid_dates
      return if @form_organization.blank?

      @media_assets = @form_organization.media_assets.ready.with_attached_file.order(created_at: :desc)
      load_order_screens
    end

    def header_update_attrs
      {
        product_name: order_params[:product_name],
        placement_kind: order_params[:placement_kind].presence || @advertising_order.placement_kind,
        shows_per_hour: order_header_shows_per_hour,
        distribution_strategy: order_params[:distribution_strategy].presence || @advertising_order.distribution_strategy
      }.compact
    end

    def media_assets_ready_scope
      @form_organization.media_assets.ready
    end

    def media_assets_organization
      @form_organization
    end

    def prepare_form
      load_form_collections
      load_occupancy
    end

    def render_form_failure(template)
      prepare_form
      render template, status: :unprocessable_content
    end

    def update_active_order!
      revise_args = {
        order: @advertising_order,
        shows_per_hour: order_header_shows_per_hour,
        distribution_strategy: order_params[:distribution_strategy].presence || @advertising_order.distribution_strategy,
        windows: order_params[:windows],
        screen_ids: form_screen_ids,
        lines: revise_lines_payload,
        grid_from: parse_grid_date(params[:grid_from]),
        grid_to: parse_grid_date(params[:grid_to])
      }
      raw_order = params[:advertising_order]
      if raw_order&.key?(:product_name)
        revise_args[:product_name] = order_params[:product_name]
      end
      if raw_order&.key?(:placement_kind)
        revise_args[:placement_kind] = order_params[:placement_kind]
      end
      if clip_ids_submitted?
        submitted_ids = submitted_media_asset_ids.map(&:to_s)
        current_ids = @advertising_order.rotation&.ordered_items&.map { |item| item.media_asset_id.to_s } || []
        if submitted_ids != current_ids
          revise_args[:media_assets] = find_media_assets
        end
      end

      result = Advertising::ReviseActiveOrder.call(**revise_args)
      flash[:warning] = t("advertising_orders.activate.quota_exceeded") if result.quota_exceeded
      redirect_to admin_advertising_order_path(@advertising_order), notice: t("advertising_orders.update.updated")
    rescue Advertising::InvalidGrid => e
      @advertising_order = e.order
      @form_organization = @advertising_order.organization
      render_form_failure(:edit)
    rescue Advertising::Error, Airtime::ConflictError => e
      @advertising_order.errors.add(:base, e.message)
      render_form_failure(:edit)
    end

    def order_params
      @order_params ||= params.fetch(:advertising_order, {}).permit(
        :organization_id,
        :product_name,
        :media_asset_id,
        { media_asset_ids: [] },
        :placement_kind,
        :shows_per_hour,
        :distribution_strategy,
        windows: [ :starts_at, :ends_at ],
        screen_ids: [],
        lines: [ :screen_id, { days: [ :date, :shows, :skipped ] } ]
      )
    end
  end
end
