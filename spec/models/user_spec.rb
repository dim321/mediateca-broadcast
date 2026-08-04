# frozen_string_literal: true

require 'rails_helper'

# == Schema Information
#
# Table name: users
#
#  id              :bigint           not null, primary key
#  email           :string           not null
#  password_digest :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_users_on_email            (email) UNIQUE
#  index_users_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
RSpec.describe User, type: :model do
  describe 'associations' do
    it 'belongs to organization' do
      user = build(:user, organization: nil)
      expect(user).not_to be_valid
    end
  end

  describe 'validations' do
    it 'requires email' do
      expect(build(:user, email: '')).not_to be_valid
    end

    it 'rejects invalid email format' do
      expect(build(:user, email: 'not-an-email')).not_to be_valid
    end

    it 'requires unique email' do
      create(:user, email: 'same@example.com')
      dup = build(:user, email: 'same@example.com')
      expect(dup).not_to be_valid
    end
  end

  describe 'normalization' do
    it 'strips and downcases email' do
      user = create(:user, email: '  Test@EXAMPLE.com  ')
      expect(user.email).to eq('test@example.com')
    end
  end

  describe 'has_secure_password' do
    it 'authenticates with correct password' do
      user = create(:user, password: 'secretsecret')
      expect(user.authenticate('secretsecret')).to eq(user)
    end

    it 'rejects wrong password' do
      user = create(:user, password: 'secretsecret')
      expect(user.authenticate('wrong')).to be_falsey
    end
  end
end
