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
        ensure_medium!(asset)
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

    def ensure_medium!(asset)
      asset.validate
      return if asset.errors[:file].any?
      return if theme.accepts_content_kind?(asset.content_kind)

      asset.errors.add(:file, :wrong_medium)
      raise ActiveRecord::RecordInvalid, asset
    end

    def build_asset
      MediaAsset.new(
        organization: theme.organization,
        uploaded_by: uploaded_by,
        content_type: ServiceTheme.content_type_for_role(role) || :service,
        visibility: :network
      ).tap { |asset| asset.file.attach(file) if file.present? }
    end
  end
end
