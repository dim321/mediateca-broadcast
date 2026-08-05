# frozen_string_literal: true

module NavigationHelper
  def nav_link_to(name, path, controllers:, **html_options)
    active = Array(controllers).map(&:to_s).include?(controller_path)
    classes = [html_options.delete(:class), ("menu-active" if active)].compact.join(" ")
    link_to name, path, html_options.merge(class: classes.presence)
  end
end
