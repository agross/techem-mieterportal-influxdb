# frozen_string_literal: true

require 'faraday'

class Consumptions
  def self.request(residential_unit, bearer_token)
    warn "Requesting consumptions for residential unit #{residential_unit}"

    base_uri = "https://mieter.techem.de/api/v1/consumptions/residential-units/#{residential_unit}/consumptions/"

    http = Faraday.new(url: base_uri,
                       headers: {
                         Authorization: "Bearer #{bearer_token}"
                       }) do |f|
      f.response(:json) # Decode response bodies as JSON.
    end

    months = http.get('periods?limit=60')

    months
      .body['data']
      .map { |d| d['period'] }
      .flat_map do |month|
        http.get(month).body['data']
      end
  end
end
