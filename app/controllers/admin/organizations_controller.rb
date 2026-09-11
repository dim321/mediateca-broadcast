# frozen_string_literal: true

module Admin
  class OrganizationsController < Admin::BaseController
    def index
      @q = Organization.ransack(ransack_params)
      @q.sorts = "name asc" if @q.sorts.empty?
      @organizations = @q.result.page(params[:page]).per(25)
    end

    def show
      @organization = Organization.includes(profile: :business_sphere).find(params[:id])
    end

    def new
      @organization = Organization.new
      @organization.build_profile
    end

    def create
      @organization = Organization.new
      @organization.build_profile
      if @organization.update(organization_params)
        redirect_to admin_organization_path(@organization), notice: t("admin.crud.created"), status: :see_other
      else
        @organization.build_profile if @organization.profile.nil?
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @organization = Organization.find(params[:id])
      @organization.build_profile if @organization.profile.nil?
    end

    def update
      @organization = Organization.find(params[:id])
      @organization.build_profile if @organization.profile.nil?
      if @organization.update(organization_params)
        redirect_to admin_organization_path(@organization), notice: t("admin.crud.updated"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @organization = Organization.find(params[:id])
      destroy_with_restriction(@organization, admin_organizations_path, notice: t("admin.crud.destroyed"))
    end

    private

    def organization_params
      params.expect(
        organization: [
          :name,
          :kind,
          :time_zone,
          { profile_attributes: [ :id, :brand, :holding, :business_sphere_id ] }
        ]
      )
    end
  end
end
