# frozen_string_literal: true

class AccountPolicy < ApplicationPolicy
  def show? = self?
  def update? = self?

  private

  def self?
    user.present? && record == user
  end
end
