# frozen_string_literal: true

require "administrate/field/base"

# Displays has_one_attached associations without requiring AttachmentDashboard.
class ActiveStorageAttachmentField < Administrate::Field::Base
  def attached?
    data.respond_to?(:attached?) && data.attached?
  end

  def filename
    return unless attached?

    data.filename.to_s
  end

  def content_type
    return unless attached?

    data.content_type
  end

  def byte_size
    return unless attached?

    data.byte_size
  end

  def to_s
    attached? ? filename : "—"
  end
end
