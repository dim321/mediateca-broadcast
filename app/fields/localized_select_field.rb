# frozen_string_literal: true

require "administrate/field/select"

class LocalizedSelectField < Administrate::Field::Select
  def selectable_options
    values = super
    return values unless resource.class.defined_enums.key?(attribute.to_s)

    values.map do |value|
      [ I18n.t("enums.#{resource.class.model_name.i18n_key}.#{attribute}.#{value}", default: value.humanize), value ]
    end
  end

  def to_s
    return super unless resource.class.defined_enums.key?(attribute.to_s)

    I18n.t(
      "enums.#{resource.class.model_name.i18n_key}.#{attribute}.#{data}",
      default: data.to_s.humanize
    )
  end
end
