# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organization, type: :model do
  describe 'associations' do
    it 'restricts destroy when users exist' do
      org = create(:organization)
      create(:user, organization: org)
      expect { org.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end
  end

  describe 'validations' do
    it 'requires name' do
      expect(build(:organization, name: '')).not_to be_valid
    end

    it 'requires time_zone' do
      expect(build(:organization, time_zone: '')).not_to be_valid
    end
  end
end
