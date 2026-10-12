# frozen_string_literal: true

module Agent
  module Commands
    class Issue < BaseService
      class Error < StandardError
        attr_reader :code

        def initialize(code)
          @code = code
          super(code)
        end
      end

      NO_PARAM_TYPES = %w[restart_stream stop wake sleep ensure_app].freeze

      def initialize(screen:, type:, params:, url_options:)
        @screen = screen
        @type = type.to_s
        @params = params.to_h.deep_stringify_keys
        @url_options = url_options.to_h.symbolize_keys
      end

      def call
        raise Error, "unknown_type" unless AgentCommand::TYPES.include?(type)

        AgentCommand.transaction do
          command = screen.station.agent_commands.create!(
            screen: screen,
            public_id: "cmd_#{SecureRandom.uuid}",
            command_type: type,
            params: normalized_params,
            issued_at: Time.current,
            status: "pending"
          )
          attach_upload_url(command)
          command
        end
      end

      private

      attr_reader :screen, :type, :params, :url_options

      def normalized_params
        case type
        when "start_stream" then start_stream_params
        when "screenshot" then {}
        when "record" then { "seconds" => record_seconds }
        when "install_apk" then install_apk_params
        when *NO_PARAM_TYPES then {}
        else
          raise Error, "unknown_type"
        end
      end

      def start_stream_params
        out = {}
        url = params["url"].to_s.strip
        out["url"] = url if url.present?
        if params["buffer_ms"].present?
          buffer = parse_integer(params["buffer_ms"], "buffer_ms_invalid")
          raise Error, "buffer_ms_invalid" if buffer.negative?

          out["buffer_ms"] = buffer
        end
        out
      end

      def record_seconds
        raw = params["seconds"]
        seconds = raw.present? ? parse_integer(raw, "seconds_out_of_range") : 10
        raise Error, "seconds_out_of_range" unless seconds.between?(1, 120)

        seconds
      end

      def install_apk_params
        url = params["url"].to_s.strip
        return {} if url.blank?
        raise Error, "url_must_be_https" unless url.start_with?("https://")

        { "url" => url }
      end

      def attach_upload_url(command)
        return unless command.expects_upload?
        raise Error, "missing_host" if url_options[:host].blank?

        command.update!(params: command.params.merge("upload_url" => upload_url(command)))
      end

      def upload_url(command)
        Rails.application.routes.url_helpers.api_agent_upload_url(
          token: ArtifactToken.generate(command.public_id),
          **url_options.compact
        )
      end

      def parse_integer(value, code)
        Integer(value)
      rescue ArgumentError, TypeError
        raise Error, code
      end
    end
  end
end
