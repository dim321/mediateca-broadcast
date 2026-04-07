# frozen_string_literal: true

class BroadcastPointsController < ApplicationController
  before_action :require_user
  before_action :set_broadcast_point, only: %i[edit update]

  def index
    authorize BroadcastPoint
    base = policy_scope(BroadcastPoint).order(:name)
    filtered = Fleet::FilterPoints.call(scope: base, tag_ids: filter_tag_ids)
    @broadcast_points = filtered.includes(:tags)
    @tags = policy_scope(Tag).order(Arel.sql("LOWER(name)"))
    @selected_tag_ids = filter_tag_ids
  end

  def new
    @broadcast_point = BroadcastPoint.new(organization: Current.user.organization)
    authorize @broadcast_point
    load_tags_for_form
  end

  def create
    @broadcast_point = BroadcastPoint.new(broadcast_point_base_params)
    @broadcast_point.organization = Current.user.organization
    authorize @broadcast_point
    if @broadcast_point.save
      sync_tags!(@broadcast_point)
      redirect_to broadcast_points_path, notice: t(".created")
    else
      repopulate_tagging_fields
      load_tags_for_form
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @broadcast_point
    load_tags_for_form
  end

  def update
    authorize @broadcast_point
    if @broadcast_point.update(broadcast_point_base_params)
      sync_tags!(@broadcast_point)
      redirect_to broadcast_points_path, notice: t(".updated")
    else
      repopulate_tagging_fields
      load_tags_for_form
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def filter_tag_ids
    raw = params[:tag_ids]
    return [] if raw.blank?

    Array(raw).map(&:to_i).reject(&:zero?)
  end

  def load_tags_for_form
    @available_tags = policy_scope(Tag).order(Arel.sql("LOWER(name)"))
  end

  def sync_tags!(point)
    permitted = tagging_params
    ids = Array(permitted[:tag_ids]).map(&:to_i).reject(&:zero?)
    names = parse_new_tag_names(permitted[:new_tag_names])
    org = point.organization
    Tag.transaction do
      from_names = names.map { |n| find_or_create_tag!(org, n) }
      allowed_ids = org.tags.where(id: ids).pluck(:id)
      point.tag_ids = (allowed_ids + from_names.map(&:id)).uniq
    end
  end

  def find_or_create_tag!(org, name)
    org.tags.where("LOWER(name) = ?", name.downcase).first_or_create! do |tag|
      tag.name = name
    end
  end

  def parse_new_tag_names(str)
    return [] if str.blank?

    str.split(",").map(&:strip).reject(&:blank?).uniq
  end

  def tagging_params
    params.require(:broadcast_point).permit(:new_tag_names, tag_ids: [])
  end

  def broadcast_point_base_params
    params.require(:broadcast_point).permit(:name, :city, :venue_label, :time_zone, :status)
  end

  def set_broadcast_point
    @broadcast_point = policy_scope(BroadcastPoint).find(params[:id])
  end

  def repopulate_tagging_fields
    permitted = begin
      tagging_params
    rescue ActionController::ParameterMissing
      {}
    end
    @broadcast_point.new_tag_names = permitted[:new_tag_names].to_s
  end

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end
end
