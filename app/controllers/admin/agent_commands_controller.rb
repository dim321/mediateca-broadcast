# frozen_string_literal: true

module Admin
  class AgentCommandsController < Admin::BaseController
    def create
      screen = Screen.find(params[:screen_id])
      raw = params.expect(agent_command: [ :command_type, :url, :buffer_ms, :seconds ])
      Agent::Commands::Issue.call(
        screen: screen,
        type: raw[:command_type].to_s,
        params: raw.slice(:url, :buffer_ms, :seconds).to_h,
        url_options: artifact_url_options
      )
      redirect_to admin_screen_path(screen), notice: t("admin.agent_commands.created"), status: :see_other
    rescue Agent::Commands::Issue::Error => error
      redirect_to admin_screen_path(screen), alert: t("admin.agent_commands.errors.#{error.code}"), status: :see_other
    end

    private

    def artifact_url_options
      if ENV["APP_HOST"].present?
        { host: ENV["APP_HOST"], protocol: ENV.fetch("APP_PROTOCOL", "https") }
      else
        { host: request.host, port: request.optional_port, protocol: request.protocol.delete_suffix("://") }
      end
    end
  end
end
