# frozen_string_literal: true

require "rails/generators"

module Admin
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def copy_controller
        copy_file "base_controller.rb", "app/controllers/admin/base_controller.rb"
        copy_file "admin_helper.rb", "app/helpers/admin_helper.rb"
      end

      def copy_layout
        copy_file "operator.html.erb", "app/views/layouts/admin/operator.html.erb"
        copy_file "_sidebar.html.erb", "app/views/admin/shared/_sidebar.html.erb"
        copy_file "_navbar.html.erb", "app/views/admin/shared/_navbar.html.erb"
        copy_file "_flash.html.erb", "app/views/admin/shared/_flash.html.erb"
        copy_file "_empty_state.html.erb", "app/views/admin/shared/_empty_state.html.erb"
      end

      def copy_javascript
        copy_file "admin.js", "app/javascript/admin.js"
        copy_file "sidebar_controller.js", "app/javascript/admin/controllers/sidebar_controller.js"
        copy_file "dropdown_controller.js", "app/javascript/admin/controllers/dropdown_controller.js"
        copy_file "modal_controller.js", "app/javascript/admin/controllers/modal_controller.js"
        copy_file "tabs_controller.js", "app/javascript/admin/controllers/tabs_controller.js"
      end

      def copy_css
        copy_file "admin.css", "app/assets/tailwind/admin.css"
      end

      def copy_kaminari
        %w[paginator page prev_page next_page first_page last_page gap].each do |partial|
          copy_file "kaminari/_#{partial}.html.erb", "app/views/kaminari/admin/_#{partial}.html.erb"
        end
      end
    end
  end
end
