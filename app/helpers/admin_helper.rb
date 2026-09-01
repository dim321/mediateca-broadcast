# frozen_string_literal: true

module AdminHelper
  NAV_ITEMS = [
    { key: :media_plans, path: :admin_media_plans_path, controllers: %w[admin/media_plans] },
    { key: :advertising_orders, path: :admin_advertising_orders_path, controllers: %w[admin/advertising_orders] },
    { key: :organizations, path: :admin_organizations_path, controllers: %w[admin/organizations] },
    { key: :users, path: :admin_users_path, controllers: %w[admin/users] },
    { key: :locations, path: :admin_locations_path, controllers: %w[admin/locations] },
    { key: :stations, path: :admin_stations_path, controllers: %w[admin/stations] },
    { key: :screens, path: :admin_screens_path, controllers: %w[admin/screens] },
    { key: :tags, path: :admin_tags_path, controllers: %w[admin/tags] },
    { key: :screen_tags, path: :admin_screen_tags_path, controllers: %w[admin/screen_tags] },
    { key: :media_assets, path: :admin_media_assets_path, controllers: %w[admin/media_assets] },
    { key: :rotations, path: :admin_rotations_path, controllers: %w[admin/rotations] },
    { key: :rotation_items, path: :admin_rotation_items_path, controllers: %w[admin/rotation_items] },
    { key: :broadcast_point_groups, path: :admin_broadcast_point_groups_path, controllers: %w[admin/broadcast_point_groups] },
    { key: :broadcast_point_group_memberships, path: :admin_broadcast_point_group_memberships_path, controllers: %w[admin/broadcast_point_group_memberships] },
    { key: :play_logs, path: :admin_play_logs_path, controllers: %w[admin/play_logs] },
    { key: :business_spheres, path: :admin_directory_business_spheres_path, controllers: %w[admin/directory/business_spheres] }
  ].freeze

  def admin_nav_items
    NAV_ITEMS
  end

  def admin_nav_active?(item)
    item[:controllers].include?(controller_path)
  end

  def admin_nav_link_options(item)
    { class: admin_nav_link_class(item) }
  end

  def admin_nav_link_class(item)
    base = "flex items-center p-2 rounded-lg group"
    if admin_nav_active?(item)
      "#{base} text-gray-900 bg-gray-100"
    else
      "#{base} text-gray-900 hover:bg-gray-100"
    end
  end

  def admin_flash_class(type)
    case type.to_s
    when "notice"
      "p-4 mb-4 text-sm text-green-800 rounded-lg bg-green-50"
    when "warning"
      "p-4 mb-4 text-sm text-yellow-800 rounded-lg bg-yellow-50"
    else
      "p-4 mb-4 text-sm text-red-800 rounded-lg bg-red-50"
    end
  end

  def admin_primary_button_class
    "text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center"
  end

  def admin_secondary_button_class
    "text-gray-900 bg-white border border-gray-300 hover:bg-gray-100 focus:ring-4 focus:ring-gray-200 font-medium rounded-lg text-sm px-5 py-2.5"
  end

  def admin_danger_button_class
    "text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:outline-none focus:ring-red-300 font-medium rounded-lg text-sm px-5 py-2.5"
  end

  def admin_input_class
    "bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5"
  end

  def admin_label_class
    "block mb-2 text-sm font-medium text-gray-900"
  end

  def admin_select_class
    admin_input_class
  end

  def admin_checkbox_class
    "w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500"
  end

  def admin_enum_label(record, attribute)
    value = record.public_send(attribute)
    return t("admin.crud.none") if value.blank?

    t("enums.#{record.model_name.i18n_key}.#{attribute}.#{value}")
  end

  def admin_enum_options(model, attribute)
    model.public_send(attribute.to_s.pluralize).keys.map do |key|
      [ t("enums.#{model.model_name.i18n_key}.#{attribute}.#{key}"), key ]
    end
  end

  def admin_record_label(record)
    return t("admin.crud.none") if record.nil?

    record.try(:name).presence ||
      record.try(:email).presence ||
      record.try(:product_name).presence ||
      "#{record.model_name.human} ##{record.id}"
  end

  def admin_link_to_record(record)
    return t("admin.crud.none") if record.nil?

    link_to admin_record_label(record), admin_record_path(record), class: "text-blue-700 hover:underline"
  end

  def admin_record_path(record)
    case record
    when ::Directory::BusinessSphere then [ :admin, :directory, record ]
    else [ :admin, record ]
    end
  end

  def admin_boolean(value)
    value ? t("admin.crud.yes") : t("admin.crud.no")
  end

  def admin_attachment_name(attachment)
    return t("admin.crud.none") unless attachment&.attached?

    attachment.filename.to_s
  end

  def admin_flash_for(resource, action)
    t("admin.#{resource}.#{action}", default: t("admin.crud.#{action}"))
  end
end
