require 'json'
require 'selenium-webdriver'

class Portal
  include Selenium::WebDriver

  OPTIONS = Chrome::Options.new(
      args: %w[
        headless
        no-sandbox
        disable-gpu
        disable-software-rasterizer
        disable-dev-shm-usage
      ]
    )

  def self.log_in_and_get_bearer_token(user, password)
    begin
      driver.get('https://mieter.techem.de/')

      accept_cookies

      begin
        attempts ||= 1

        driver.find_element(:css, 'button[data-test-id="cta-global-header-login"]')
              .click
      rescue Error::ElementClickInterceptedError
        accept_cookies

        if attempts += 1 <= 5
          warn 'Retrying because click on login button was intercepted'
          retry
        else
          raise 'Failed to click login button'
        end
      end

      driver.find_element(:id, 'signInName').send_keys(user)
      driver.find_element(:id, 'password').send_keys(password)
      driver.find_element(:css, 'button[type="submit"]').click

      Wait.new.until do
        driver.current_url.include?('/consumptions')
      end

      extract_bearer_token
    ensure
      driver.quit
    end
  end

  private

  def self.driver
    @driver ||= begin
      driver = Selenium::WebDriver.for(:remote,
                                       url: 'http://chrome:9515',
                                       options: OPTIONS)
      driver.manage.timeouts.implicit_wait = 10

      driver
    end
  end

  def self.accept_cookies
    Wait.new(timeout: 15).until do
      driver.find_element(:id, 'CybotCookiebotDialogBodyUnderlay')
    end

    driver.execute_script(<<~SCRIPT)
      document.querySelectorAll('#CybotCookiebotDialogBodyUnderlay, #CybotCookiebotDialog')
              .forEach(x => x.remove())
    SCRIPT
  end

  def self.extract_bearer_token
    # Extract JSON items from local storage (not all are parsable as JSON).
    values = driver.local_storage.map do |k, v|
      begin
        JSON.parse(v)
      rescue JSON::ParserError
        nil
      end
    end

    # Extract bearer token from local storage.
    error = ->() { raise 'Could not find bearer token' }
    token = values.find(error) do |v|
      v['credentialType'] == 'AccessToken' &&
      v['tokenType'] == 'Bearer'
    end

    token['secret']
  end
end
