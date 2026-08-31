# frozen_string_literal: true

module Admin
  module Directory
    class BusinessSpheresController < Admin::ApplicationController
      def destroy
        requested_resource.destroy!
        redirect_to after_resource_destroyed_path(requested_resource),
          notice: translate_with_resource("destroy.success")
      rescue ActiveRecord::DeleteRestrictionError
        redirect_to admin_directory_business_spheres_path,
          alert: t("admin.business_spheres.destroy_restricted")
      end
    end
  end
end
