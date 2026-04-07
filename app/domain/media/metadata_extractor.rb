# frozen_string_literal: true

require "json"
require "open3"

module Media
  class MetadataExtractor
    Result = Data.define(:duration_seconds, :metadata, :refined_content_kind)

    class << self
      def call(path, declared_content_type: nil)
        stdout, _stderr, status = Open3.capture3(
          "ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", path
        )
        unless status.success?
          return fallback_result(declared_content_type:, error: "ffprobe_failed")
        end

        data = JSON.parse(stdout)
        streams = Array(data["streams"])
        format = data["format"] || {}

        duration_seconds = format["duration"].present? ? format["duration"].to_f.to_i : nil
        metadata = {
          "format" => format.slice("format_name", "bit_rate"),
          "streams" => streams.map { |s| s.slice("codec_type", "codec_name", "width", "height") }
        }

        refined = refine_kind_from_streams(streams, declared_content_type:)

        Result.new(
          duration_seconds: duration_seconds,
          metadata: metadata,
          refined_content_kind: refined
        )
      rescue JSON::ParserError => e
        fallback_result(declared_content_type:, error: e.message)
      end

      private

      def refine_kind_from_streams(streams, declared_content_type:)
        types = streams.filter_map { |s| s["codec_type"] }.uniq
        if types.include?("video")
          "video"
        elsif types.include?("audio")
          "audio"
        elsif declared_content_type&.start_with?("image/")
          "image"
        end
      end

      def fallback_result(declared_content_type:, error:)
        kind =
          if declared_content_type&.start_with?("video/") then "video"
          elsif declared_content_type&.start_with?("audio/") then "audio"
          elsif declared_content_type&.start_with?("image/") then "image"
          elsif declared_content_type == "application/pdf" then "document"
          elsif declared_content_type&.include?("presentation") then "presentation"
          end

        Result.new(
          duration_seconds: nil,
          metadata: { "probe_error" => error },
          refined_content_kind: kind
        )
      end
    end
  end
end
