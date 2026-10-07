# frozen_string_literal: true

module AdminHelper
  NAV_SECTIONS = [
    {
      key: :orders,
      items: [
        { key: :advertising_orders, path: :admin_advertising_orders_path, controllers: %w[admin/advertising_orders] },
        { key: :media_plans, path: :admin_media_plans_path, controllers: %w[admin/media_plans] }
      ]
    },
    {
      key: :clients,
      items: [
        { key: :organizations, path: :admin_organizations_path, controllers: %w[admin/organizations] },
        { key: :users, path: :admin_users_path, controllers: %w[admin/users] }
      ]
    },
    {
      key: :screen_fleet,
      items: [
        { key: :locations, path: :admin_locations_path, controllers: %w[admin/locations] },
        { key: :stations, path: :admin_stations_path, controllers: %w[admin/stations] },
        { key: :screens, path: :admin_screens_path, controllers: %w[admin/screens] },
        { key: :broadcast_point_groups, path: :admin_broadcast_point_groups_path, controllers: %w[admin/broadcast_point_groups] },
        { key: :screen_tags, path: :admin_screen_tags_path, controllers: %w[admin/screen_tags] },
        { key: :broadcast_point_group_memberships, path: :admin_broadcast_point_group_memberships_path, controllers: %w[admin/broadcast_point_group_memberships] }
      ]
    },
    {
      key: :media_library,
      items: [
        { key: :media_assets, path: :admin_media_assets_path, controllers: %w[admin/media_assets] },
        { key: :rotations, path: :admin_rotations_path, controllers: %w[admin/rotations] },
        { key: :rotation_items, path: :admin_rotation_items_path, controllers: %w[admin/rotation_items] }
      ]
    },
    {
      items: [
        { key: :play_logs, path: :admin_play_logs_path, controllers: %w[admin/play_logs] }
      ]
    },
    {
      key: :directories,
      items: [
        { key: :business_spheres, path: :admin_directory_business_spheres_path, controllers: %w[admin/directory/business_spheres] },
        { key: :tags, path: :admin_tags_path, controllers: %w[admin/tags] }
      ]
    }
  ].freeze

  NAV_ITEMS = NAV_SECTIONS.flat_map { |section| section.fetch(:items) }.freeze

  # Heroicons solid mini (20×20) paths for sidebar group headers.
  NAV_GROUP_ICON_PATHS = {
    orders: "M2 6a2 2 0 012-2h12a2 2 0 012 2v2a2 2 0 100 4v2a2 2 0 01-2 2H4a2 2 0 01-2-2v-2a2 2 0 100-4V6z",
    clients: "M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z",
    screen_fleet: "M3 4a1 1 0 011-1h12a1 1 0 011 1v8a1 1 0 01-1 1H4a1 1 0 01-1-1V4zm2 10a1 1 0 00-1 1v1a1 1 0 001 1h10a1 1 0 001-1v-1a1 1 0 00-1-1H5z",
    media_library: "M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z",
    service_library: "M4 2a2 2 0 00-2 2v11a3 3 0 106 0V4a2 2 0 00-2-2H4zm1 14a1 1 0 100-2 1 1 0 000 2zm8-14a2 2 0 00-2 2v11a3 3 0 106 0V4a2 2 0 00-2-2h-2zm1 14a1 1 0 100-2 1 1 0 000 2z",
    directories: "M9 4.804A7.968 7.968 0 005.5 4c-1.255 0-2.443.29-3.5.804v10A7.969 7.969 0 015.5 14c1.669 0 3.218.51 4.5 1.385A7.962 7.962 0 0114.5 14c1.255 0 2.443.29 3.5.804v-10A7.968 7.968 0 0014.5 4c-1.255 0-2.443.29-3.5.804V12a1 1 0 11-2 0V4.804z"
  }.freeze

  def admin_nav_sections
    NAV_SECTIONS
  end

  def admin_nav_items
    NAV_ITEMS
  end

  def admin_nav_active?(item)
    item[:controllers].include?(controller_path)
  end

  def admin_nav_section_active?(section)
    section.fetch(:items).any? { |item| admin_nav_active?(item) }
  end

  def admin_nav_group_icon(key)
    path = NAV_GROUP_ICON_PATHS[key.to_sym]
    return if path.blank?

    tag.svg(
      class: "w-4 h-4 shrink-0 text-gray-500",
      "aria-hidden": "true",
      xmlns: "http://www.w3.org/2000/svg",
      fill: "currentColor",
      viewBox: "0 0 20 20"
    ) do
      tag.path(d: path)
    end
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
