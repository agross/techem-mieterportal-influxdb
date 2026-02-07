#!/usr/bin/env ruby

require_relative './lib/portal.rb'
require_relative './lib/consumptions.rb'
require_relative './lib/influxdb.rb'

USER = ENV.fetch('PORTAL_USER')
PASSWORD = ENV.fetch('PORTAL_PASSWORD')

INFLUXDB_ADDRESS = ENV.fetch('INFLUXDB_ADDRESS')
INFLUXDB_TOKEN = ENV.fetch('INFLUXDB_TOKEN')
INFLUXDB_ORG = ENV.fetch('INFLUXDB_ORG')
INFLUXDB_BUCKET = ENV.fetch('INFLUXDB_BUCKET')

residential_unit, token = Portal.log_in(USER, PASSWORD)
consumptions = Consumptions.request(residential_unit, token)
InfluxDb.store(INFLUXDB_ADDRESS,
               INFLUXDB_TOKEN,
               INFLUXDB_ORG,
               INFLUXDB_BUCKET,
               consumptions)
