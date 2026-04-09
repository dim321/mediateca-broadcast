# frozen_string_literal: true

module Avo
  module Resources
    class ApplicationResource < Avo::BaseResource
      abstract_resource!

      self.index_query = lambda {
        rel = query
        klass = rel.respond_to?(:klass) ? rel.klass : rel
        next rel unless klass.column_names.include?("organization_id")

        org_id = Avo::Current.context[:organization_id]
        next rel.none if org_id.blank?

        rel.where(organization_id: org_id)
      }

      self.find_record_method = lambda {
        rel = query
        klass = rel.respond_to?(:klass) ? rel.klass : rel
        if klass.column_names.include?("organization_id")
          org_id = Avo::Current.context[:organization_id]
          rel = org_id.present? ? rel.where(organization_id: org_id) : rel.none
        end
        rel.find(id)
      }
    end
  end
end
