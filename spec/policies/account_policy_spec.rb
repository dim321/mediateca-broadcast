# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountPolicy do
  subject(:policy) { described_class.new(user, record) }

  let(:user) { build_stubbed(:user) }

  describe "#show? / #update?" do
    context "when the record is the current user" do
      let(:record) { user }

      it { is_expected.to be_show }
      it { is_expected.to be_update }
    end

    context "when the record is another user" do
      let(:record) { build_stubbed(:user) }

      it { is_expected.not_to be_show }
      it { is_expected.not_to be_update }
    end
  end
end
