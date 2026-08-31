# frozen_string_literal: true

module Admin
  class AdvertisingOrdersController < Admin::ApplicationController
    helper AdvertisingOrdersHelper

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
        coefficient_percent: order_params[:coefficient_percent].presence || 0,
        discount_cents: discount_cents_from_params
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
      @advertising_order = requested_resource
      @form_organization = @advertising_order.organization
      prepare_form
    end

    def update
      @advertising_order = requested_resource
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
      result = Advertising::ActivateOrder.call(order: requested_resource)
      flash[:notice] = t("advertising_orders.activate.activated")
      flash[:warning] = t("advertising_orders.activate.quota_exceeded") if result.quota_exceeded
      if result.conflicted_windows.any?
        flash[:alert] = t("advertising_orders.activate.conflicts", count: result.conflicted_windows.size)
      end
      redirect_to admin_advertising_order_path(requested_resource)
    rescue Advertising::Error => e
      redirect_to admin_advertising_order_path(requested_resource), alert: e.message
    end

    def cancel
      Advertising::CancelOrder.call(order: requested_resource)
      redirect_to admin_advertising_order_path(requested_resource),
        notice: t("admin.advertising_orders.cancelled")
    end

    private

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
      own_groups = @form_organization.broadcast_point_groups.to_a
      owner_groups = BroadcastPointGroup.commercial_eligible_groups_for(@form_organization).to_a
      @broadcast_point_groups = (own_groups + owner_groups).uniq.sort_by(&:name)
    end

    def persist_grid!(order)
      payload = lines_params
      return if payload.empty?

      order.advertising_order_lines.reset
      Advertising::UpdateGrid.call(order: order, lines: payload)
    end

    def lines_params
      raw = order_params[:lines]
      list = raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash) ? raw.values : Array(raw)
      list.filter_map do |line|
        group_id = line[:broadcast_point_group_id]
        next if group_id.blank?

        {
          broadcast_point_group_id: group_id.to_i,
          price_per_day_cents: line[:price_per_day_rubles].to_i * 100,
          days: Array(line[:days]).map { |day| { date: day[:date], shows: day[:shows] } }
        }
      end
    end

    def header_update_attrs
      {
        product_name: order_params[:product_name],
        coefficient_percent: order_params[:coefficient_percent].presence || 0,
        discount_cents: discount_cents_from_params,
        placement_kind: order_params[:placement_kind].presence || @advertising_order.placement_kind
      }.compact
    end

    def discount_cents_from_params
      order_params[:discount_rubles].to_i * 100
    end

    def find_media_asset
      return if @form_organization.blank?

      @form_organization.media_assets.find_by(id: order_params[:media_asset_id])
    end

    def find_placement_group
      id = occupancy_group_id
      return if id.blank? || @form_organization.blank?

      @form_organization.broadcast_point_groups.find_by(id: id) ||
        BroadcastPointGroup.commercial_eligible_groups_for(@form_organization).find_by(id: id)
    end

    def occupancy_group_id
      order_params[:broadcast_point_group_id].presence ||
        @advertising_order&.advertising_order_lines&.first&.broadcast_point_group_id
    end

    def load_occupancy
      group = find_placement_group
      @occupied_slots = if group
        Airtime::OccupancyPresenter.call(broadcast_point_group: group)
      else
        []
      end
    end

    def grid_dates
      from = parse_grid_date(params[:grid_from]) || order_grid_bounds&.begin || Date.current.beginning_of_month
      to = parse_grid_date(params[:grid_to]) || order_grid_bounds&.end || Date.current.end_of_month
      from, to = to, from if from > to
      (from..to).to_a
    end

    def order_grid_bounds
      dates = @advertising_order&.advertising_order_lines&.flat_map do |line|
        line.advertising_order_line_days.map(&:date)
      end&.compact
      return if dates.blank?

      dates.min..dates.max
    end

    def parse_grid_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def ensure_form_lines
      @advertising_order.advertising_order_lines.build if @advertising_order.advertising_order_lines.empty?
    end

    def prepare_form
      load_form_collections
      ensure_form_lines
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
        :coefficient_percent,
        :discount_rubles,
        :broadcast_point_group_id,
        lines: [ :broadcast_point_group_id, :price_per_day_rubles, { days: [ :date, :shows ] } ]
      )
    end
  end
end
