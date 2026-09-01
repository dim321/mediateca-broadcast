# frozen_string_literal: true

module Admin
  module Directory
    class BusinessSpheresController < Admin::BaseController
      def index
        @q = ::Directory::BusinessSphere.ransack(ransack_params)
        @q.sorts = "name asc" if @q.sorts.empty?
        @business_spheres = @q.result.page(params[:page]).per(25)
      end

      def show
        @business_sphere = ::Directory::BusinessSphere.find(params[:id])
      end

      def new
        @business_sphere = ::Directory::BusinessSphere.new
      end

      def create
        @business_sphere = ::Directory::BusinessSphere.new(business_sphere_params)
        if @business_sphere.save
          redirect_to admin_directory_business_sphere_path(@business_sphere),
            notice: t("admin.crud.created"), status: :see_other
        else
          render :new, status: :unprocessable_content
        end
      end

      def edit
        @business_sphere = ::Directory::BusinessSphere.find(params[:id])
      end

      def update
        @business_sphere = ::Directory::BusinessSphere.find(params[:id])
        if @business_sphere.update(business_sphere_params)
          redirect_to admin_directory_business_sphere_path(@business_sphere),
            notice: t("admin.crud.updated"), status: :see_other
        else
          render :edit, status: :unprocessable_content
        end
      end

      def destroy
        @business_sphere = ::Directory::BusinessSphere.find(params[:id])
        destroy_with_restriction(
          @business_sphere,
          admin_directory_business_spheres_path,
          notice: t("admin.crud.destroyed"),
          alert: t("admin.business_spheres.destroy_restricted")
        )
      end

      private

      def business_sphere_params
        params.expect(directory_business_sphere: [ :name ])
      end
    end
  end
end
