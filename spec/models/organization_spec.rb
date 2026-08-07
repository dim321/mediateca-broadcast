# frozen_string_literal: true

require 'rails_helper'

# == Schema Information
#
# Table name: organizations
#
#  id         :bigint           not null, primary key
#  kind       :string           default("client"), not null
#  name       :string           not null
#  time_zone  :string           default("UTC"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_organizations_one_operator  (kind) UNIQUE WHERE ((kind)::text = 'operator'::text)
#
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

  describe 'kind' do
    it 'defaults to client' do
      expect(build(:organization)).to be_client
    end

    it 'supports operator organizations' do
      expect(build(:organization, :operator)).to be_operator
    end

    it 'allows only one operator organization' do
      create(:organization, :operator)

      expect(build(:organization, :operator)).not_to be_valid
    end

    it 'allows many client organizations' do
      create(:organization, :client)

      expect(build(:organization, :client)).to be_valid
    end
  end
end
