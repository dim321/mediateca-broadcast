# frozen_string_literal: true

module ServiceThemes
  class AddClip < BaseService
    def initialize(theme:, role:, file:, uploaded_by:)
      @theme = theme
      @role = role
      @file = file
      @uploaded_by = uploaded_by
    end

    def call
      raise ArgumentError, "unknown service theme role #{role.inspect}" if theme.rotation_for(role).blank?

      asset = nil
      ServiceTheme.transaction do
        asset = build_asset
        asset.save!
      end
      asset
    rescue StandardError => e
      raise unless asset&.persisted? && Media::StorageErrors.network?(e)

      ProcessMediaMetadataJob.perform_later(asset.id)
      asset
    end

    private

    attr_reader :theme, :role, :file, :uploaded_by

    def build_asset
      MediaAsset.new(
        organization: theme.organization,
        uploaded_by: uploaded_by,
        content_type: :service,
        visibility: :network
      ).tap { |asset| asset.file.attach(file) if file.present? }
    end
  end
end
