# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistPolicy do
  let(:org) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:user) { create(:user, organization: org) }
  let(:playlist) { create(:playlist, organization: org) }

  describe "show?" do
    it "разрешает плейлист своей организации" do
      expect(described_class.new(user, playlist).show?).to be true
    end

    it "запрещает плейлист другой организации" do
      foreign = create(:playlist, organization: other_org)
      expect(described_class.new(user, foreign).show?).to be false
    end
  end

  describe "destroy?" do
    it "разрешает удаление в своей организации" do
      expect(described_class.new(user, playlist).destroy?).to be true
    end

    it "запрещает удаление в чужой организации" do
      foreign = create(:playlist, organization: other_org)
      expect(described_class.new(user, foreign).destroy?).to be false
    end
  end

  describe "Scope" do
    it "ограничивает выборку organization_id пользователя" do
      create(:playlist, organization: org)
      create(:playlist, organization: other_org)

      resolved = described_class::Scope.new(user, ::Playlist.all).resolve
      expect(resolved.map(&:organization_id).uniq).to eq([ org.id ])
    end
  end
end
