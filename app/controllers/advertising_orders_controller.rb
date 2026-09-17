# frozen_string_literal: true

class AdvertisingOrdersController < ApplicationController
  include AdvertisingOrderGrid

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
    load_occupancy
  end

  def create
    @advertising_order = policy_scope(AdvertisingOrder).new(organization: Current.user.organization)
    authorize @advertising_order

    media_assets = find_media_assets
    if media_assets.empty?
      @advertising_order.errors.add(:media_asset, :blank)
      return render_form_failure(:new)
    end

    @advertising_order = Advertising::CreateOrder.call(
      organization: Current.user.organization,
      created_by: Current.user,
      media_assets: media_assets,
      product_name: order_params[:product_name],
      placement_kind: order_params[:placement_kind].presence || :own_atmosphere,
      shows_per_hour: order_header_shows_per_hour,
      distribution_strategy: order_params[:distribution_strategy].presence || :linear
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
    load_occupancy
  end

  def update
    authorize @advertising_order
    AdvertisingOrder.transaction do
      @advertising_order.update!(header_update_attrs)
      if clip_ids_submitted?
        Advertising::UpdateOrderClips.call(order: @advertising_order, media_assets: find_media_assets)
      end
      persist_grid!(@advertising_order)
    end
    redirect_to @advertising_order, notice: t(".updated")
  rescue Advertising::InvalidGrid => e
    @advertising_order = e.order
    render_form_failure(:edit)
  rescue Advertising::Error => e
    @advertising_order.errors.add(:media_asset, e.message)
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
    render layout: "print"
  end

  def replace_clip
    authorize @advertising_order
    load_replacement_assets

    return if request.get? || request.head?

    media_assets = find_replacement_media_assets
    if media_assets.empty?
      @advertising_order.errors.add(:media_asset, :blank)
      return render :replace_clip, status: :unprocessable_content
    end

    Advertising::UpdateOrderClips.call(order: @advertising_order, media_assets: media_assets)
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
      .includes(
        { rotation: { rotation_items: { media_asset: { file_attachment: :blob } } } },
        advertising_order_lines: [ :screen, :advertising_order_line_days ]
      )
      .find(params[:id])
  end

  def load_form_collections
    @media_assets = policy_scope(MediaAsset).ready.with_attached_file.order(created_at: :desc)
    @grid_dates = grid_dates
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

  def find_replacement_media_assets
    ids = Array(params[:media_asset_ids]).map(&:presence).compact
    ids = Array(order_params[:media_asset_ids]).map(&:presence).compact if ids.empty?
    ids = [ params[:media_asset_id].presence ].compact if ids.empty?
    find_ordered_media_assets(ids)
  end

  def load_replacement_assets
    @media_assets = media_assets_ready_scope.with_attached_file.order(created_at: :desc)
  end

  def media_assets_ready_scope
    policy_scope(MediaAsset).ready
  end

  def media_assets_organization
    Current.user.organization
  end

  def render_form_failure(template)
    load_form_collections
    load_occupancy
    render template, status: :unprocessable_content
  end

  def order_params
    @order_params ||= params.fetch(:advertising_order, {}).permit(
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
