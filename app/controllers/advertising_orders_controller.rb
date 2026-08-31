# frozen_string_literal: true

class AdvertisingOrdersController < ApplicationController
  before_action :require_user
  before_action :set_advertising_order, only: %i[show edit update destroy activate cancel print replace_clip]
  before_action :load_form_collections, only: %i[new create edit update]

  def index
    authorize AdvertisingOrder
    @advertising_orders = policy_scope(AdvertisingOrder).includes(:media_asset).order(created_at: :desc)
    @advertising_orders = @advertising_orders.where(status: params[:status]) if params[:status].present?
  end

  def show
    authorize @advertising_order
    @coverage = Advertising::GridCoverage.call(order: @advertising_order)
  end

  def new
    @advertising_order = policy_scope(AdvertisingOrder).new(
      organization: Current.user.organization,
      placement_kind: :own_atmosphere
    )
    authorize @advertising_order
    ensure_form_lines
    load_occupancy
  end

  def create
    @advertising_order = policy_scope(AdvertisingOrder).new(organization: Current.user.organization)
    authorize @advertising_order

    asset = find_media_asset
    unless asset
      @advertising_order.errors.add(:media_asset, :blank)
      return render_form_failure(:new)
    end

    @advertising_order = Advertising::CreateOrder.call(
      organization: Current.user.organization,
      created_by: Current.user,
      media_asset: asset,
      product_name: order_params[:product_name],
      placement_kind: order_params[:placement_kind].presence || :own_atmosphere,
      coefficient_percent: order_params[:coefficient_percent].presence || 0,
      discount_cents: discount_cents_from_params
    )
    persist_grid!(@advertising_order)
    redirect_to @advertising_order, notice: t(".created")
  rescue Advertising::InvalidGrid => e
    @advertising_order = e.order
    render_form_failure(:edit)
  rescue ActiveRecord::RecordInvalid => e
    @advertising_order = e.record if e.record.is_a?(AdvertisingOrder)
    @advertising_order ||= policy_scope(AdvertisingOrder).new(organization: Current.user.organization)
    render_form_failure(:new)
  end

  def edit
    authorize @advertising_order
    ensure_form_lines
    load_occupancy
  end

  def update
    authorize @advertising_order
    @advertising_order.update!(header_update_attrs)
    persist_grid!(@advertising_order)
    redirect_to @advertising_order, notice: t(".updated")
  rescue Advertising::InvalidGrid => e
    @advertising_order = e.order
    render_form_failure(:edit)
  rescue ActiveRecord::RecordInvalid
    render_form_failure(:edit)
  end

  def destroy
    authorize @advertising_order
    rotation = @advertising_order.rotation
    AdvertisingOrder.transaction do
      @advertising_order.destroy!
      rotation.reload.destroy!
    end
    redirect_to advertising_orders_path, notice: t(".destroyed")
  end

  def activate
    authorize @advertising_order
    result = Advertising::ActivateOrder.call(order: @advertising_order)
    flash[:notice] = t(".activated")
    flash[:warning] = t(".quota_exceeded") if result.quota_exceeded
    if result.conflicted_windows.any?
      flash[:alert] = t(".conflicts", count: result.conflicted_windows.size)
    end
    redirect_to advertising_order_path(@advertising_order)
  rescue Advertising::Error => e
    redirect_to advertising_order_path(@advertising_order), alert: e.message
  end

  def cancel
    authorize @advertising_order
    Advertising::CancelOrder.call(order: @advertising_order)
    redirect_to advertising_order_path(@advertising_order), notice: t(".cancelled")
  end

  def print
    authorize @advertising_order
  end

  def replace_clip
    authorize @advertising_order
    load_replacement_assets

    return if request.get? || request.head?

    asset = find_replacement_asset
    unless asset
      @advertising_order.errors.add(:media_asset, :blank)
      return render :replace_clip, status: :unprocessable_content
    end

    Advertising::ReplaceClip.call(order: @advertising_order, media_asset: asset)
    redirect_to advertising_order_path(@advertising_order), notice: t(".replaced")
  rescue Advertising::Error => e
    flash.now[:alert] = e.message
    render :replace_clip, status: :unprocessable_content
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_advertising_order
    @advertising_order = policy_scope(AdvertisingOrder)
      .includes(advertising_order_lines: [ :broadcast_point_group, :advertising_order_line_days ])
      .find(params[:id])
  end

  def load_form_collections
    @media_assets = policy_scope(MediaAsset).ready.with_attached_file.order(created_at: :desc)
    own_groups = policy_scope(BroadcastPointGroup).to_a
    owner_groups = BroadcastPointGroup.commercial_eligible_groups_for(Current.user.organization).to_a
    @broadcast_point_groups = (own_groups + owner_groups).uniq.sort_by(&:name)
    @grid_dates = grid_dates
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
    policy_scope(MediaAsset).find_by(id: order_params[:media_asset_id])
  end

  def find_replacement_asset
    policy_scope(MediaAsset).find_by(id: params[:media_asset_id])
  end

  def load_replacement_assets
    @media_assets = policy_scope(MediaAsset).ready.with_attached_file.order(created_at: :desc).select do |asset|
      asset.id != @advertising_order.media_asset_id && asset.broadcast_ready?
    end
  end

  def find_placement_group
    id = occupancy_group_id
    policy_scope(BroadcastPointGroup).find_by(id: id) ||
      BroadcastPointGroup.commercial_eligible_groups_for(Current.user.organization).find_by(id: id)
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

  def render_form_failure(template)
    load_form_collections
    ensure_form_lines
    load_occupancy
    render template, status: :unprocessable_content
  end

  def order_params
    @order_params ||= params.fetch(:advertising_order, {}).permit(
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
