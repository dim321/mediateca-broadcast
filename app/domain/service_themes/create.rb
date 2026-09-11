# frozen_string_literal: true

module ServiceThemes
  class Create < BaseService
    def initialize(organization:, name:)
      @organization = organization
      @name = name
    end

    def call
      ensure_creatable!

      ServiceTheme.transaction do
        rotations = build_rotations
        theme = ServiceTheme.new(
          organization: organization,
          name: name.to_s.strip,
          header_start_rotation: rotations.fetch(:header_start),
          header_end_rotation: rotations.fetch(:header_end),
          welcome_rotation: rotations.fetch(:welcome),
          close_rotation: rotations.fetch(:close)
        )
        theme.save!
        theme
      end
    end

    private

    attr_reader :organization, :name

    def ensure_creatable!
      theme = ServiceTheme.new(organization: organization, name: name.to_s.strip)
      unless organization&.operator?
        theme.errors.add(:organization, :must_be_operator)
        raise ActiveRecord::RecordInvalid, theme
      end
      if theme.name.blank?
        theme.errors.add(:name, :blank)
        raise ActiveRecord::RecordInvalid, theme
      end
      return unless ServiceTheme.exists?(organization_id: organization.id, name: theme.name)

      theme.errors.add(:name, :taken)
      raise ActiveRecord::RecordInvalid, theme
    end

    def build_rotations
      ServiceTheme::ROTATION_ROLES.keys.index_with do |role|
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
