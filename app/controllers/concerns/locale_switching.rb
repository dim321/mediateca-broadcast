# frozen_string_literal: true

module LocaleSwitching
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
  end

  private

  def switch_locale(&action)
    locale = session[:locale].presence || I18n.default_locale
    locale = I18n.default_locale unless I18n.available_locales.map(&:to_s).include?(locale.to_s)

    I18n.with_locale(locale, &action)
  end
end
