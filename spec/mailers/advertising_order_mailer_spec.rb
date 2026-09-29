# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdvertisingOrderMailer, type: :mailer do
  describe "#draft_created" do
    it "sends the draft notice to the author" do
      order = create(:advertising_order, product_name: "Triumph")
      notice = I18n.t("advertising_orders.create.created", name: "Triumph")

      mail = described_class.draft_created(order)

      expect(mail.to).to eq([ order.created_by.email ])
      expect(mail.subject).to eq(notice)
      expect(mail.text_part.body.decoded).to include(notice)
      expect(mail.html_part.body.decoded).to include(notice)
    end
  end
end
