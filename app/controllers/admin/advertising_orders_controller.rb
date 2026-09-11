# frozen_string_literal: true

module Admin
  class AdvertisingOrdersController < Admin::BaseController
    include AdvertisingOrderGrid

    helper AdvertisingOrdersHelper

    def index
      @q = AdvertisingOrder.ransack(ransack_params)
      @q.sorts = "created_at desc" if @q.sorts.empty?
      @advertising_orders = @q.result.includes(:organization, :created_by).page(params[:page]).per(25)
    end

    def show
      @advertising_order = find_order
    end

    def new
      @form_organization = selected_organization
      @advertising_order = AdvertisingOrder.new(
        organization: @form_organization,
        placement_kind: :own_atmosphere
      )
      prepare_form
    end

    def create
      @form_organization = selected_organization
      asset = find_media_asset
      unless asset
        @advertising_order = AdvertisingOrder.new(organization: @form_organization)
        @advertising_order.errors.add(:media_asset, :blank)
        return render_form_failure(:new)
      end

      @advertising_order = Advertising::CreateOrder.call(
        organization: @form_organization,
        created_by: Current.user,
        media_asset: asset,
        product_name: order_params[:product_name],
        placement_kind: order_params[:placement_kind].presence || :own_atmosphere,
        shows_per_hour: order_header_shows_per_hour
      )
      persist_grid!(@advertising_order)
      redirect_to admin_advertising_order_path(@advertising_order), notice: t("advertising_orders.create.created")
    rescue Advertising::InvalidGrid => e
      @advertising_order = e.order
      @form_organization = @advertising_order.organization
      render_form_failure(:edit)
    rescue ActiveRecord::RecordInvalid => e
      @advertising_order = e.record if e.record.is_a?(AdvertisingOrder)
      @advertising_order ||= AdvertisingOrder.new(organization: @form_organization)
      render_form_failure(:new)
    end

    def edit
      @advertising_order = find_order
      @form_organization = @advertising_order.organization
      prepare_form
    end

    def update
      @advertising_order = find_order
      @form_organization = @advertising_order.organization
      @advertising_order.update!(header_update_attrs)
      persist_grid!(@advertising_order)
      redirect_to admin_advertising_order_path(@advertising_order), notice: t("advertising_orders.update.updated")
    rescue Advertising::InvalidGrid => e
      @advertising_order = e.order
      @form_organization = @advertising_order.organization
      render_form_failure(:edit)
    rescue ActiveRecord::RecordInvalid
      render_form_failure(:edit)
    end

    def activate
      order = find_order
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

    def cancel
      order = find_order
      Advertising::CancelOrder.call(order: order)
      redirect_to admin_advertising_order_path(order),
        notice: t("admin.advertising_orders.cancelled")
    end

    private

    def find_order
      AdvertisingOrder.includes(advertising_order_lines: [ :screen, :advertising_order_line_days ]).find(params[:id])
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
        shows_per_hour: order_header_shows_per_hour
      }.compact
    end

    def find_media_asset
      return if @form_organization.blank?

      @form_organization.media_assets.find_by(id: order_params[:media_asset_id])
    end

    def prepare_form
      load_form_collections
      load_occupancy
    end

    def render_form_failure(template)
      prepare_form
      render template, status: :unprocessable_content
    end

    def order_params
      @order_params ||= params.fetch(:advertising_order, {}).permit(
        :organization_id,
        :product_name,
        :media_asset_id,
        :placement_kind,
        :shows_per_hour,
        windows: [ :starts_at, :ends_at ],
        screen_ids: [],
        lines: [ :screen_id, { days: [ :date, :shows, :skipped ] } ]
      )
    end
  end
end
