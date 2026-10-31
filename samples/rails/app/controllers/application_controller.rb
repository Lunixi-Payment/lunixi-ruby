# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  http_basic_authenticate_with name: ENV.fetch('DEMO_USERNAME'), password: ENV.fetch('DEMO_PASSWORD')
  around_action :use_locale

  private

  def use_locale(&)
    locale = params[:locale].to_s
    locale = 'en' unless %w[en tr].include?(locale)
    I18n.with_locale(locale, &)
  end
end
