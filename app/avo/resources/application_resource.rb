# frozen_string_literal: true

module Avo
  module Resources
    class ApplicationResource < Avo::BaseResource
      abstract_resource!

      self.index_query = lambda {
        Avo::Resources::ApplicationResource.scope_to_current_organization(query)
      }

      self.find_record_method = lambda {
        Avo::Resources::ApplicationResource.scope_to_current_organization(query).find(id)
      }

      def self.scope_to_current_organization(rel)
        klass = rel.respond_to?(:klass) ? rel.klass : rel
        org_id = Avo::Current.context[:organization_id]
        return rel.none if org_id.blank?

        if klass.name == "Organization"
          rel.where(id: org_id)
        elsif klass.column_names.include?("organization_id")
          rel.where(organization_id: org_id)
        else
          rel
        end
      end
    end
  end
end
