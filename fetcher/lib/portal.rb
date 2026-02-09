# frozen_string_literal: true

require 'ferrum'
require 'json'
require 'jwt'
require_relative './wait'

class Portal
  class << self
    def log_in(user, password)
      driver.go_to('https://mieter.techem.de/')

      accept_cookies

      warn 'Finding login button'
      login = Wait.until { driver.at_css('button.btn-outline-primary') }

      warn 'Clicking login button'
      login.click

      warn 'Filling login form'
      Wait.until do
        u = driver.at_css('input#signInName')
        p = driver.at_css('#password')

        u&.focusable? && p&.focusable?
      end
      driver.at_css('input#signInName').focus.type(user)
      driver.at_css('#password').focus.type(password)

      warn 'Submitting login form'
      driver.at_css('button[type="submit"]').scroll_into_view.click

      Wait.until(timeout: 10) do
        warn "Expecting consumptions page #{driver.current_url}"
        driver.current_url.include?('/consumptions')
      end

      token = extract_bearer_token
      residential_unit = extract_residential_unit(token)
      [residential_unit, token]
    rescue StandardError
      driver&.screenshot(full: true, path: "/screenshots/#{Time.now}.png")
      raise
    ensure
      driver.quit
    end

    private

    def driver
      @driver ||= if ENV.include?('LOCAL')
                    Ferrum::Browser.new(headless: false)
                  else
                    Ferrum::Browser.new(ws_url: 'ws://chrome:3000')
                  end
    end

    def accept_cookies
      warn 'Finding cookie underlay'
      Wait.until { driver.at_css('#CybotCookiebotDialogBodyUnderlay') }

      warn 'Removing cookie underlay'
      elements = driver.css('#CybotCookiebotDialogBodyUnderlay, #CybotCookiebotDialog')
      elements.each(&:remove)
    end

    def extract_bearer_token
      warn 'Extracting bearer token'

      # Extract JSON items from local storage (not all are parsable as JSON).
      local_storage = driver.evaluate('window.localStorage')

      values = local_storage.map do |_k, v|
        JSON.parse(v)
      rescue JSON::ParserError, TypeError
        {}
      end

      # Extract bearer token from local storage.
      error = -> { raise 'Could not find bearer token' }
      token = values.find(error) do |v|
        v['credentialType'] == 'AccessToken' &&
          v['tokenType'] == 'Bearer' &&
          v['target'] == 'https://techemtenantportal.onmicrosoft.com/eedo-be-consumption-service/access_as_user'
      end

      token['secret']
    end

    def extract_residential_unit(token)
      warn 'Extracting residential unit'

      jwt = JWT::EncodedToken.new(token)
      jwt
        .unverified_payload['rentalAgreements']
        .first
        .split(';')
        .first
    end
  end
end
