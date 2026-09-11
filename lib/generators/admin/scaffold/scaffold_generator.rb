# frozen_string_literal: true

require "rails/generators"
require "rails/generators/named_base"
require "rails/generators/resource_helpers"
require "rails/generators/generated_attribute"

module Admin
  module Generators
    class ScaffoldGenerator < Rails::Generators::NamedBase
      include Rails::Generators::ResourceHelpers

      source_root File.expand_path("templates", __dir__)
      argument :attributes, type: :array, default: [], banner: "field:type field:type"

      def create_controller
        template "controller.rb.tt", File.join("app/controllers/admin", "#{controller_file_name}_controller.rb")
      end

      def create_views
        %w[index show new edit _form].each do |view|
          template "#{view}.html.erb.tt", File.join("app/views/admin", controller_file_name, "#{view}.html.erb")
        end
      end

      def create_request_spec
        template "request_spec.rb.tt", File.join("spec/requests/admin", "#{controller_file_name}_spec.rb")
      end

      def inject_ransackable
        model_path = File.join("app/models", "#{file_name}.rb")
        absolute_model_path = File.expand_path(model_path, destination_root)
        return unless File.exist?(absolute_model_path)

        sentinel = "def self.ransackable_attributes"
        return if File.read(absolute_model_path).include?(sentinel)

        inject_into_class model_path, class_name, <<~RUBY
          def self.ransackable_attributes(_auth_object = nil)
            %w[#{ransackable_attribute_list}]
          end

          def self.ransackable_associations(_auth_object = nil)
            []
          end

        RUBY
      end

      def remind_routes
        say "Add `resources :#{controller_file_name}` inside `namespace :admin` in config/routes.rb if it is missing.", :yellow
        say "Add a sidebar item in app/helpers/admin_helper.rb.", :yellow
      end

      private

      def show_route_helper
        "admin_#{singular_table_name}"
      end

      def index_route_helper
        "admin_#{plural_table_name}"
      end

      def permitted_params
        form_attributes.map { |attr| ":#{attr.name}" }.join(", ")
      end

      def ransackable_attribute_list
        names = attributes.map(&:name)
        names = %w[id name created_at updated_at] if names.empty?
        (names | %w[id created_at updated_at]).uniq.join(" ")
      end

      def searchable_attribute
        string_attr = attributes.find { |attr| attr.type.to_s == "string" }
        string_attr&.name || attributes.first&.name || "name"
      end

      def form_attributes
        return attributes if attributes.present?

        [ Rails::Generators::GeneratedAttribute.new("name", "string") ]
      end
    end
  end
end
