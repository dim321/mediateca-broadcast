# frozen_string_literal: true

class ScheduleRulesController < ApplicationController
  before_action :require_user
  before_action :set_schedule_rule, only: %i[show edit update destroy]
  before_action :load_form_collections, only: %i[new create edit update]

  def index
    authorize ScheduleRule
    @schedule_rules = policy_scope(ScheduleRule)
      .includes(:playlist, :point_groups)
      .order(starts_at: :desc)
  end

  def show
    authorize @schedule_rule
  end

  def new
    @schedule_rule = policy_scope(ScheduleRule).new(organization: Current.user.organization)
    authorize @schedule_rule
  end

  def edit
    authorize @schedule_rule
  end

  def create
    @schedule_rule = policy_scope(ScheduleRule).new(organization: Current.user.organization)
    authorize @schedule_rule
    assign_rule_attributes(@schedule_rule)
    if save_rule_with_targets(@schedule_rule)
      redirect_to schedule_rules_path, notice: t(".created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    authorize @schedule_rule
    assign_rule_attributes(@schedule_rule)
    if save_rule_with_targets(@schedule_rule)
      redirect_to schedule_rules_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @schedule_rule
    @schedule_rule.destroy!
    redirect_to schedule_rules_path, notice: t(".destroyed")
  end

  private

  def require_user
    return if Current.user

    redirect_to login_path, alert: t("media_assets.authentication_required")
  end

  def set_schedule_rule
    @schedule_rule = policy_scope(ScheduleRule).find(params[:id])
  end

  def load_form_collections
    @playlists = policy_scope(Playlist).order(:name)
    @point_groups = policy_scope(PointGroup).order(:name)
  end

  def assign_rule_attributes(rule)
    playlist = policy_scope(Playlist).find_by(id: schedule_rule_params[:playlist_id])
    if playlist.blank?
      rule.errors.add(:playlist, :blank)
    else
      rule.playlist = playlist
    end

    tc = schedule_rule_params[:timezone_context]
    rule.timezone_context = tc if tc.present?

    apply_parsed_times(rule)
  end

  def apply_parsed_times(rule)
    starts_param = schedule_rule_params[:starts_at]
    ends_param = schedule_rule_params[:ends_at]
    if starts_param.blank? || ends_param.blank?
      rule.errors.add(:starts_at, :blank)
      return
    end

    rule.starts_at, rule.ends_at = Scheduling::TimeWindowResolver.utc_range(
      organization: Current.user.organization,
      starts_at_param: starts_param,
      ends_at_param: ends_param
    )
  rescue ArgumentError, TypeError
    rule.errors.add(:starts_at, :invalid)
  end

  def save_rule_with_targets(rule)
    return false if rule.errors.any?

    group_ids = normalized_point_group_ids
    if group_ids.empty?
      rule.errors.add(:base, :must_have_targets)
      return false
    end

    ScheduleRule.transaction do
      rule.schedule_targets.destroy_all if rule.persisted?
      group_ids.each do |gid|
        rule.schedule_targets.build(point_group_id: gid)
      end
      rule.save!
    end
    true
  rescue ActiveRecord::RecordInvalid
    rule.association(:schedule_targets).reset if rule.persisted?
    false
  end

  def normalized_point_group_ids
    ids = Array(schedule_rule_params[:point_group_ids]).compact_blank.map(&:to_i).uniq
    policy_scope(PointGroup).where(id: ids).pluck(:id)
  end

  def schedule_rule_params
    params.require(:schedule_rule).permit(:playlist_id, :starts_at, :ends_at, :timezone_context, point_group_ids: [])
  end
end
