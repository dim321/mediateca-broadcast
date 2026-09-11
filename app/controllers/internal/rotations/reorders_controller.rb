# frozen_string_literal: true

module Internal
  module Rotations
    class ReordersController < ApplicationController
      before_action :require_user
      before_action :set_rotation

      def update
        authorize @rotation, :reorder?
        ::Rotations::ReorderItems.call(rotation: @rotation, ordered_ids: reorder_ids)
        head :no_content
      rescue ArgumentError
        head :unprocessable_content
      end

      private

      def require_user
        return if Current.user

        head :unauthorized
      end

      def set_rotation
        @rotation = policy_scope(Rotation).find(params[:rotation_id])
      end

      def reorder_ids
        raw = params.permit(rotation_item_ids: [])[:rotation_item_ids]
        raise ArgumentError if raw.blank? || !raw.is_a?(Array)

        raw.map(&:to_i)
      end
    end
  end
end
