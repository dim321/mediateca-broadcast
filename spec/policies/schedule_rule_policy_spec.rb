# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduleRulePolicy do
  let(:org) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:user) { create(:user, organization: org) }
  let(:rule) do
    create(:schedule_rule,
      organization: org,
      playlist: create(:playlist, organization: org),
      point_group: create(:point_group, organization: org))
  end

  describe "show?" do
    it "разрешает правило своей организации" do
      expect(described_class.new(user, rule).show?).to be true
    end

    it "запрещает правило другой организации" do
      foreign = create(:schedule_rule,
        organization: other_org,
        playlist: create(:playlist, organization: other_org),
        point_group: create(:point_group, organization: other_org))
      expect(described_class.new(user, foreign).show?).to be false
    end
  end

  describe "destroy?" do
    it "разрешает удаление в своей организации" do
      expect(described_class.new(user, rule).destroy?).to be true
    end

    it "запрещает удаление в чужой организации" do
      foreign = create(:schedule_rule,
        organization: other_org,
        playlist: create(:playlist, organization: other_org),
        point_group: create(:point_group, organization: other_org))
      expect(described_class.new(user, foreign).destroy?).to be false
    end
  end

  describe "Scope" do
    it "ограничивает расписания по organization_id" do
      rule
      create(:schedule_rule,
        organization: other_org,
        playlist: create(:playlist, organization: other_org),
        point_group: create(:point_group, organization: other_org))

      resolved = described_class::Scope.new(user, ScheduleRule.all).resolve
      expect(resolved.map(&:organization_id).uniq).to eq([ org.id ])
    end
  end
end
