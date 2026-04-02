# frozen_string_literal: true

require 'rails_helper'

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
