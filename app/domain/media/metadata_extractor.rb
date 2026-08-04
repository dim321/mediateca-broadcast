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
        # Prefer declared MIME: ffprobe reports still images (PNG/JPEG) as codec_type=video.
        kind_from_declared_mime(declared_content_type) || kind_from_streams(streams)
      end

      def kind_from_declared_mime(content_type)
        if content_type&.start_with?("image/")
          "image"
        elsif content_type&.start_with?("video/")
          "video"
        elsif content_type&.start_with?("audio/")
          "audio"
        elsif content_type == "application/pdf"
          "document"
        elsif content_type&.include?("presentation")
          "presentation"
        end
      end

      def kind_from_streams(streams)
        types = streams.filter_map { |stream| stream["codec_type"] }.uniq
        if types.include?("video")
          "video"
        elsif types.include?("audio")
          "audio"
        end
      end

      def fallback_result(declared_content_type:, error:)
        Result.new(
          duration_seconds: nil,
          metadata: { "probe_error" => error },
          refined_content_kind: kind_from_declared_mime(declared_content_type)
        )
      end
    end
  end
end
