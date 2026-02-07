# frozen_string_literal: true

require 'json'
require 'jwt'
require 'selenium-webdriver'

class Portal
  OPTIONS = Selenium::WebDriver::Chrome::Options.new(args: %w[
                                                       headless
                                                       no-sandbox
                                                       disable-gpu
                                                       disable-software-rasterizer
                                                       disable-dev-shm-usage
                                                     ])

  class << self
    def log_in(user, password)
      driver.get('https://mieter.techem.de/')

      accept_cookies

      warn 'Finding login button'
      login = driver.find_element(:css, 'button.btn-outline-primary')

      warn 'Clicking login button'
      login.click

      warn 'Filling login form'
      driver.find_element(:id, 'signInName').send_keys(user)
      driver.find_element(:id, 'password').send_keys(password)
      warn 'Submitting login form'
      driver.find_element(:css, 'button[type="submit"]').send_keys(:return)

      wait.until do
        warn 'Expecting consumptions page'
        driver.current_url.include?('/consumptions')
      end

      token = extract_bearer_token
      residential_unit = extract_residential_unit(token)
      [residential_unit, token]
    ensure
      driver.quit
    end

    private

    def driver
      @driver ||= begin
        driver = Selenium::WebDriver.for(:remote,
                                         url: 'http://chrome:9515',
                                         options: OPTIONS)
        driver.manage.timeouts.implicit_wait = 10

        driver
      end
    end

    def wait
      Selenium::WebDriver::Wait.new(timeout: driver.manage.timeouts.implicit_wait,
                                    interval: 1)
    end

    def accept_cookies
      warn 'Finding cookie underlay'
      driver.find_element(:id, 'CybotCookiebotDialogBodyUnderlay')

      warn 'Removing cookie underlay'
      driver.execute_script(<<~SCRIPT)
        document.querySelectorAll('#CybotCookiebotDialogBodyUnderlay, #CybotCookiebotDialog')
                .forEach(x => x.remove())
      SCRIPT
    end

    def extract_bearer_token
      warn 'Extracting bearer token'

      # Extract JSON items from local storage (not all are parsable as JSON).
      local_storage = driver.execute_script('return window.localStorage')
      values = local_storage.map do |_k, v|
        JSON.parse(v)
      rescue JSON::ParserError, TypeError
        nil
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
      jwt = JWT::EncodedToken.new(token)
      jwt
        .unverified_payload['rentalAgreements']
        .first
        .split(';')
        .first
    end
  end
end
