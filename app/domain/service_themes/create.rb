# frozen_string_literal: true

module ServiceThemes
  class Create < BaseService
    def initialize(organization:, name:, medium: "video")
      @organization = organization
      @name = name
      @medium = medium.presence || "video"
    end

    def call
      ensure_creatable!

      ServiceTheme.transaction do
        rotations = build_rotations
        theme = ServiceTheme.new(
          organization: organization,
          name: name.to_s.strip,
          medium: medium,
          header_start_rotation: rotations.fetch(:header_start),
          header_end_rotation: rotations.fetch(:header_end),
          welcome_rotation: rotations.fetch(:welcome),
          close_rotation: rotations.fetch(:close),
          neutral_rotation: rotations.fetch(:neutral)
        )
        theme.save!
        theme
      end
    end

    private

    attr_reader :organization, :name, :medium

    def ensure_creatable!
      theme = ServiceTheme.new(organization: organization, name: name.to_s.strip, medium: safe_medium)
      unless organization&.operator?
        theme.errors.add(:organization, :must_be_operator)
        raise ActiveRecord::RecordInvalid, theme
      end
      if theme.name.blank?
        theme.errors.add(:name, :blank)
        raise ActiveRecord::RecordInvalid, theme
      end
      unless ServiceTheme.media.key?(medium.to_s)
        theme.errors.add(:medium, :inclusion)
        raise ActiveRecord::RecordInvalid, theme
      end
      return unless ServiceTheme.exists?(organization_id: organization.id, name: theme.name)

      theme.errors.add(:name, :taken)
      raise ActiveRecord::RecordInvalid, theme
    end

    def safe_medium
      ServiceTheme.media.key?(medium.to_s) ? medium.to_s : "video"
    end

    def build_rotations
      ServiceTheme::FOLDER_ROLES.index_with do |role|
        organization.rotations.create!(
          name: rotation_name(role),
          system_managed: true
        )
      end
    end

    def rotation_name(role)
      "#{name.to_s.strip} · #{role}"
    end
  end
end
