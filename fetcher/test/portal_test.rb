# frozen_string_literal: true

require 'minitest/autorun'
require 'uri'
require_relative '../lib/portal'

class PortalTest < Minitest::Test
  Response = Struct.new(:status, :headers, :body, keyword_init: true)

  class FakeConnection
    attr_reader :requests

    def initialize(&handler)
      @handler = handler
      @requests = []
    end

    def run_request(method, url, body, headers)
      request = { method: method, url: url, body: body, headers: headers }
      @requests << request
      @handler.call(request, @requests.length)
    end
  end

  def teardown
    Portal.instance_variable_set(:@connection, nil)
  end

  def test_log_in_performs_pkce_flow_and_returns_consumption_token
    access_token = jwt(rentalAgreements: ['unit-123;agreement-456'])
    authorize_state = nil
    fake = FakeConnection.new do |request, number|
      case number
      when 1
        query = URI.decode_www_form(URI(request[:url]).query).to_h
        authorize_state = query.fetch('state')
        assert_equal 'S256', query['code_challenge_method']
        assert_equal 'fragment', query['response_mode']
        assert_equal Portal::REDIRECT_URI, query['redirect_uri']
        assert_includes query['scope'], 'eedo-be-consumption-service/access_as_user'

        settings = {
          csrf: 'csrf-token',
          transId: 'StateProperties=transaction-id',
          hosts: {
            tenant: '/techemtenantportal.onmicrosoft.com/B2C_1A_signin',
            policy: 'B2C_1A_signin'
          },
          api: 'CombinedSigninAndSignup',
          isPageViewIdSentWithHeader: true,
          pageViewId: 'page-view-id'
        }
        Response.new(
          status: 200,
          headers: { 'set-cookie' => 'session=first; Path=/; HttpOnly' },
          body: "<script>var SETTINGS = #{JSON.generate(settings)};</script>"
        )
      when 2
        assert_equal :post, request[:method]
        assert_includes(
          request[:url],
          '/techemtenantportal.onmicrosoft.com/B2C_1A_signin/SelfAsserted?'
        )
        refute_includes request[:url], '/B2C_1A_signin/B2C_1A_signin/'
        assert_equal 'session=first', request[:headers]['Cookie']
        assert_equal 'page-view-id', request[:headers]['x-ms-cpim-pageviewid']
        credentials = URI.decode_www_form(request[:body]).to_h
        assert_equal 'person@example.com', credentials['signInName']
        assert_equal 'secret & safe', credentials['password']

        Response.new(
          status: 200,
          headers: { 'Set-Cookie' => 'session=second; Path=/, auth=accepted; Path=/' },
          body: '{"status":"200"}'
        )
      when 3
        assert_equal :get, request[:method]
        assert_includes(
          request[:url],
          '/techemtenantportal.onmicrosoft.com/B2C_1A_signin/api/' \
          'CombinedSigninAndSignup/confirmed?'
        )
        refute_includes request[:url], '/B2C_1A_signin/B2C_1A_signin/'
        assert_equal 'session=second; auth=accepted', request[:headers]['Cookie']

        location = "#{Portal::REDIRECT_URI}##{URI.encode_www_form(
          code: 'authorization-code',
          state: authorize_state
        )}"
        Response.new(status: 302, headers: { 'Location' => location }, body: '')
      when 4
        assert_equal :post, request[:method]
        assert_equal Portal::TOKEN_ENDPOINT, request[:url]
        token_request = URI.decode_www_form(request[:body]).to_h
        assert_equal 'authorization-code', token_request['code']
        assert_equal Portal::REDIRECT_URI, token_request['redirect_uri']
        assert_equal(
          Portal.send(:generate_code_challenge, token_request.fetch('code_verifier')),
          URI.decode_www_form(URI(fake.requests.first[:url]).query).to_h['code_challenge']
        )

        Response.new(
          status: 200,
          headers: {},
          body: JSON.generate(access_token: access_token, refresh_token: 'refresh-token')
        )
      else
        flunk "Unexpected request #{number}: #{request.inspect}"
      end
    end
    Portal.instance_variable_set(:@connection, fake)

    residential_unit, returned_token = Portal.log_in(
      'person@example.com',
      'secret & safe'
    )

    assert_equal 'unit-123', residential_unit
    assert_equal access_token, returned_token
    assert_equal 4, fake.requests.length
  end

  def test_authenticate_rejects_authorize_page_without_settings
    fake = FakeConnection.new do |_request, _number|
      Response.new(status: 200, headers: {}, body: '<html>login changed</html>')
    end
    Portal.instance_variable_set(:@connection, fake)

    error = assert_raises(Portal::AuthenticationError) do
      Portal.send(:authenticate, 'person@example.com', 'secret')
    end

    assert_equal 'Could not find SETTINGS in authorize page', error.message
  end

  def test_extract_settings_handles_braces_inside_json_strings
    settings = Portal.send(
      :extract_settings,
      '<script>var SETTINGS = {"csrf":"value } still inside","hosts":{}};</script>'
    )

    assert_equal 'value } still inside', settings['csrf']
  end

  def test_policy_url_does_not_duplicate_policy
    url = Portal.send(
      :policy_url,
      '/techemtenantportal.onmicrosoft.com/B2C_1A_signin',
      'B2C_1A_signin',
      'SelfAsserted'
    )

    assert_equal(
      'https://techemtenantportal.b2clogin.com/' \
      'techemtenantportal.onmicrosoft.com/B2C_1A_signin/SelfAsserted',
      url
    )
  end

  private

  def jwt(payload)
    header = Portal.send(:encode_base64url, JSON.generate(alg: 'none', typ: 'JWT'))
    body = Portal.send(:encode_base64url, JSON.generate(payload))
    "#{header}.#{body}."
  end
end
