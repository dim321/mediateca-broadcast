# frozen_string_literal: true

require "base64"
require "stringio"
require "open3"
require "tempfile"

module Media
  class PreviewGenerator
    # 1×1 PNG (минимальный плейсхолдер для аудио/документов)
    PLACEHOLDER_PNG = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ).freeze

    class << self
      def call(media_asset, file_path)
        case media_asset.content_kind
        when "video"
          attach_video_frame(media_asset, file_path)
        when "image"
          attach_image_copy(media_asset)
        else
          attach_placeholder(media_asset)
        end
      end

      private

      def attach_video_frame(media_asset, file_path)
        outfile = Tempfile.new([ "preview", ".jpg" ])
        outfile.close
        _out, err, status = Open3.capture3(
          "ffmpeg", "-y", "-ss", "00:00:01", "-i", file_path,
          "-frames:v", "1", "-q:v", "3", outfile.path
        )
        raise "ffmpeg failed: #{err}" unless status.success? && File.exist?(outfile.path) && File.size(outfile.path).positive?

        jpeg_data = File.binread(outfile.path)
        media_asset.preview.attach(
          io: StringIO.new(jpeg_data),
          filename: "preview.jpg",
          content_type: "image/jpeg"
        )
      ensure
        outfile&.unlink
      end

      def attach_image_copy(media_asset)
        return attach_placeholder(media_asset) unless media_asset.file.attached?

        media_asset.preview.attach(media_asset.file.blob)
      end

      def attach_placeholder(media_asset)
        media_asset.preview.attach(
          io: StringIO.new(PLACEHOLDER_PNG),
          filename: "preview.png",
          content_type: "image/png"
        )
      end
    end
  end
end
