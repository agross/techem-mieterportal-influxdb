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

      warn 'Finding login button'
      login = driver.find_element(:css, 'button[data-test-id="cta-global-header-login"]')

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

  def self.wait
    Wait.new(timeout: driver.manage.timeouts.implicit_wait, interval: 1)
  end

  def self.accept_cookies
    warn 'Finding cookie underlay'
    driver.find_element(:id, 'CybotCookiebotDialogBodyUnderlay')

    warn 'Removing cookie underlay'
    driver.execute_script(<<~SCRIPT)
      document.querySelectorAll('#CybotCookiebotDialogBodyUnderlay, #CybotCookiebotDialog')
              .forEach(x => x.remove())
    SCRIPT
  end

  def self.extract_bearer_token
    warn 'Extracting bearer token'

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
