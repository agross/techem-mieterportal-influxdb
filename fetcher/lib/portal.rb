# frozen_string_literal: true

require 'digest'
require 'faraday'
require 'json'
require 'securerandom'
require 'uri'

class Portal
  CLIENT_ID = 'e2c8cff8-17bc-41c7-89b6-5bee13c7f556'
  AUTHORIZE_ENDPOINT = 'https://techemtenantportal.b2clogin.com/' \
                       'techemtenantportal.onmicrosoft.com/' \
                       'b2c_1a_signin/oauth2/v2.0/authorize'
  SCOPE = 'https://techemtenantportal.onmicrosoft.com/' \
          'eedo-be-consumption-service/access_as_user openid profile offline_access'
  REDIRECT_URI = 'https://mieter.techem.de/auth'
  SERVICE_URL = 'https://techemtenantportal.b2clogin.com'
  TOKEN_ENDPOINT = 'https://techemtenantportal.b2clogin.com/' \
                   'techemtenantportal.onmicrosoft.com/' \
                   'b2c_1a_signin/oauth2/v2.0/token'
  REQUEST_TIMEOUT = 30

  class AuthenticationError < StandardError; end
  class ConnectionError < StandardError; end

  class << self
    def log_in(user, password)
      token = authenticate(user, password).fetch('access_token')
      [extract_residential_unit(token), token]
    end

    private

    def authenticate(user, password)
      warn 'Authenticating with OAuth PKCE'

      code_verifier = generate_code_verifier
      state = encode_base64url(
        JSON.generate(id: SecureRandom.uuid, meta: { interactionType: 'redirect' })
      )
      authorize_params = {
        client_id: CLIENT_ID,
        scope: SCOPE,
        redirect_uri: REDIRECT_URI,
        'client-request-id': SecureRandom.uuid,
        response_mode: 'fragment',
        response_type: 'code',
        'x-client-SKU': 'msal.js.browser',
        'x-client-VER': '2.26.0',
        client_info: '1',
        code_challenge: generate_code_challenge(code_verifier),
        code_challenge_method: 'S256',
        nonce: SecureRandom.uuid,
        state: state
      }
      authorize_url = url_with_query(AUTHORIZE_ENDPOINT, authorize_params)

      authorize_response = request(
        :get,
        authorize_url,
        headers: {
          'Accept' => 'text/html,application/xhtml+xml,application/xml;' \
                      'q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8'
        }
      )
      require_status!(authorize_response, 200, 'Authorize request failed')
      settings = extract_settings(authorize_response.body)
      cookies = capture_cookies(authorize_response)

      csrf_token = settings.fetch('csrf')
      transaction_id = settings.fetch('transId')
      tenant = settings.fetch('hosts').fetch('tenant')
      policy = settings.fetch('hosts').fetch('policy')
      api_name = settings.fetch('api')

      self_asserted_headers = {
        'Accept' => 'application/json, text/javascript, */*; q=0.01',
        'X-CSRF-TOKEN' => csrf_token,
        'X-Requested-With' => 'XMLHttpRequest',
        'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
        'Origin' => SERVICE_URL,
        'Referer' => authorize_url,
        'Cookie' => cookie_header(cookies)
      }
      if settings['isPageViewIdSentWithHeader'] && settings['pageViewId']
        self_asserted_headers['x-ms-cpim-pageviewid'] = settings['pageViewId']
      end

      self_asserted_url = policy_url(
        tenant,
        policy,
        "SelfAsserted?#{URI.encode_www_form(tx: transaction_id, p: policy)}"
      )
      login_response = request(
        :post,
        self_asserted_url,
        body: URI.encode_www_form(
          request_type: 'RESPONSE',
          signInName: user,
          password: password
        ),
        headers: self_asserted_headers
      )
      require_status!(login_response, 200, 'Login failed')
      require_login_accepted!(login_response)
      cookies = capture_cookies(login_response, cookies)

      confirmed_url = policy_url(
        tenant,
        policy,
        'api',
        api_name,
        "confirmed?#{URI.encode_www_form(
          rememberMe: false,
          csrf_token: csrf_token,
          tx: transaction_id,
          p: policy
        )}"
      )
      confirmed_response = request(
        :get,
        confirmed_url,
        headers: {
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Referer' => authorize_url,
          'Cookie' => cookie_header(cookies)
        }
      )
      require_status!(confirmed_response, 302, 'Confirmation failed')

      location = response_header(confirmed_response, 'Location')
      raise AuthenticationError, 'Confirmation redirect missing Location header' if location.to_s.empty?

      oauth_result = URI.decode_www_form(URI(location).fragment.to_s).to_h
      auth_code = oauth_result['code']
      raise AuthenticationError, 'No authorization code in redirect fragment' if auth_code.to_s.empty?

      warn 'OAuth state parameter mismatch (non-fatal)' if oauth_result['state'] && oauth_result['state'] != state

      token_response = request(
        :post,
        TOKEN_ENDPOINT,
        body: URI.encode_www_form(
          grant_type: 'authorization_code',
          client_id: CLIENT_ID,
          scope: SCOPE,
          code: auth_code,
          redirect_uri: REDIRECT_URI,
          code_verifier: code_verifier,
          client_info: '1'
        ),
        headers: {
          'Content-Type' => 'application/x-www-form-urlencoded;charset=utf-8',
          'Origin' => 'https://mieter.techem.de'
        }
      )
      token_data = parse_json(token_response.body)
      unless token_response.status == 200 && token_data.is_a?(Hash) && token_data['access_token']
        error = token_data.is_a?(Hash) && (token_data['error_description'] || token_data['error'])
        raise AuthenticationError, "Token exchange failed: #{error || "HTTP #{token_response.status}"}"
      end

      warn 'OAuth PKCE login succeeded'
      token_data
    rescue KeyError, JSON::ParserError, URI::InvalidURIError => e
      raise AuthenticationError, "Invalid login response: #{e.message}"
    end

    def connection
      @connection ||= Faraday.new do |faraday|
        faraday.options.timeout = REQUEST_TIMEOUT
        faraday.options.open_timeout = REQUEST_TIMEOUT
      end
    end

    def request(method, url, body: nil, headers: {})
      connection.run_request(method, url, body, headers)
    rescue Faraday::Error => e
      raise ConnectionError, "Techem login request failed: #{e.message}"
    end

    def generate_code_verifier
      encode_base64url(SecureRandom.random_bytes(32))
    end

    def generate_code_challenge(verifier)
      encode_base64url(Digest::SHA256.digest(verifier))
    end

    def encode_base64url(value)
      [value].pack('m0').tr('+/', '-_').delete('=')
    end

    def decode_base64url(value)
      padding = '=' * ((4 - (value.length % 4)) % 4)
      (value.tr('-_', '+/') + padding).unpack1('m0')
    end

    def extract_settings(html)
      marker = 'var SETTINGS = '
      start = html.to_s.index(marker)
      raise AuthenticationError, 'Could not find SETTINGS in authorize page' unless start

      start += marker.length
      raise AuthenticationError, 'Unexpected SETTINGS format' unless html[start] == '{'

      depth = 0
      in_string = false
      escaped = false
      finish = nil

      html.each_char.with_index do |character, index|
        next if index < start

        if in_string
          if escaped
            escaped = false
          elsif character == '\\'
            escaped = true
          elsif character == '"'
            in_string = false
          end
          next
        end

        case character
        when '"'
          in_string = true
        when '{'
          depth += 1
        when '}'
          depth -= 1
          if depth.zero?
            finish = index + 1
            break
          end
        end
      end

      raise AuthenticationError, 'Unbalanced braces in SETTINGS JSON' unless finish

      JSON.parse(html[start...finish])
    end

    def capture_cookies(response, existing = {})
      response_cookies = response_header(response, 'Set-Cookie')
      Array(response_cookies).flat_map { |header| split_set_cookie(header) }.each_with_object(existing.dup) do |cookie, all|
        name, value = cookie.split(';', 2).first.split('=', 2)
        all[name.strip] = value if name && value
      end
    end

    def split_set_cookie(header)
      header.to_s.split(/,(?=\s*[^;,=\s]+=[^;,]*)/)
    end

    def cookie_header(cookies)
      cookies.map { |name, value| "#{name}=#{value}" }.join('; ')
    end

    def require_login_accepted!(response)
      result = parse_json(response.body)
      return unless result.is_a?(Hash)
      return if [nil, 200, '200'].include?(result['status'])

      error = result['message'] || result['status'] || 'Unknown'
      raise AuthenticationError, "Login rejected: #{error}"
    end

    def require_status!(response, expected, message)
      return if response.status == expected

      raise AuthenticationError,
            "#{message} with status #{response.status}: #{response.body.to_s[0, 200]}"
    end

    def parse_json(value)
      JSON.parse(value)
    rescue JSON::ParserError, TypeError
      nil
    end

    def response_header(response, name)
      response.headers[name] || response.headers[name.downcase]
    end

    def url_with_query(url, params)
      "#{url}?#{URI.encode_www_form(params)}"
    end

    def policy_url(tenant, policy, *parts)
      tenant_path = tenant.to_s.gsub(%r{\A/+|/\z}, '')
      policy_path = policy.to_s.gsub(%r{\A/+|/\z}, '')
      policy_parts = tenant_path.split('/').last.casecmp?(policy_path) ? [] : [policy_path]
      service_url(tenant_path, *policy_parts, *parts)
    end

    def service_url(*parts)
      ([SERVICE_URL] + parts)
        .map { |part| part.to_s.gsub(%r{\A/+|/\z}, '') }
        .join('/')
    end

    def extract_residential_unit(token)
      payload_segment = token.to_s.split('.')[1]
      raise AuthenticationError, 'Access token is not a JWT' unless payload_segment

      payload = JSON.parse(decode_base64url(payload_segment))
      agreement = payload.fetch('rentalAgreements').first
      unit = if agreement.is_a?(Hash)
               agreement['residentialUnitId']
             else
               agreement.to_s.split(';').first
             end
      raise AuthenticationError, 'Access token missing residential unit' if unit.to_s.empty?

      unit
    rescue JSON::ParserError, KeyError => e
      raise AuthenticationError, "Invalid access token: #{e.message}"
    end
  end
end
