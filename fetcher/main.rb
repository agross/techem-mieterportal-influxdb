#!/usr/bin/env ruby

require_relative './lib/portal.rb'
require_relative './lib/consumptions.rb'
require_relative './lib/influxdb.rb'

USER = ENV.fetch('PORTAL_USER')
PASSWORD = ENV.fetch('PORTAL_PASSWORD')
RESIDENTIAL_UNIT = ENV.fetch('PORTAL_RESIDENTIAL_UNIT')

INFLUXDB_ADDRESS = ENV.fetch('INFLUXDB_ADDRESS')
INFLUXDB_TOKEN = ENV.fetch('INFLUXDB_TOKEN')
INFLUXDB_ORG = ENV.fetch('INFLUXDB_ORG')
INFLUXDB_BUCKET = ENV.fetch('INFLUXDB_BUCKET')


token = Portal.log_in_and_get_bearer_token(USER, PASSWORD)
consumptions = Consumptions.request(RESIDENTIAL_UNIT, token)
InfluxDb.store(INFLUXDB_ADDRESS,
               INFLUXDB_TOKEN,
               INFLUXDB_ORG,
               INFLUXDB_BUCKET,
               consumptions)
