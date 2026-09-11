# frozen_string_literal: true

require "open3"

module Media
  class TsEncoder
    class EncodingError < StandardError; end

    class << self
      def call(input_path, output_path)
        _stdout, stderr, status = Open3.capture3(*command(input_path, output_path))

        return if status.success? && File.exist?(output_path) && File.size(output_path).positive?

        raise EncodingError, "ffmpeg failed: #{stderr}"
      end

      private

      def command(input_path, output_path)
        [
          "ffmpeg", "-y", "-i", input_path,
          "-vf", "setpts=PTS-STARTPTS,scale=-2:1080:force_original_aspect_ratio=decrease",
          "-r", "25",
          "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.1",
          "-g", "25", "-keyint_min", "25", "-sc_threshold", "0", "-pix_fmt", "yuv420p",
          "-c:a", "aac", "-ar", "48000", "-b:a", "128k",
          "-af", "asetpts=PTS-STARTPTS",
          "-f", "mpegts", output_path
        ]
      end
    end
  end
end
