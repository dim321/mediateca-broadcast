# frozen_string_literal: true

module Agent
  class StoreArtifact < BaseService
    MAX_BYTES = 100.megabytes
    CONTENT_TYPES = {
      "screenshot" => "image/png",
      "record" => "video/mp4"
    }.freeze
    FILENAMES = {
      "screenshot" => "screenshot.png",
      "record" => "record.mp4"
    }.freeze

    def initialize(command:, io:, content_type:)
      @command = command
      @io = io
      @content_type = content_type
    end

    def call
      command.artifact.attach(
        io: io,
        filename: FILENAMES.fetch(command.command_type),
        content_type: content_type
      )
      command.artifact.blob
    end

    private

    attr_reader :command, :io, :content_type
  end
end
