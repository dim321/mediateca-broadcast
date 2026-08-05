# frozen_string_literal: true

class Avo::Resources::User < Avo::Resources::ApplicationResource
  def fields
    field :id, as: :id
    field :email, as: :text
    field :password, as: :password, revealable: true
    field :password_confirmation, as: :password, revealable: true
    field :role, as: :select, enum: ::User.roles
    field :organization, as: :belongs_to
  end
end
