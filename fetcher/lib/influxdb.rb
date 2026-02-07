# frozen_string_literal: true

require 'influxdb-client'

class InfluxDb
  class << self
    def store(address, token, org, bucket, consumptions)
      data = map(consumptions)

      InfluxDB2::Client.use(address,
                            token,
                            use_ssl: address.start_with?('https://'),
                            org: org,
                            bucket: bucket,
                            debugging: true,
                            precision: InfluxDB2::WritePrecision::SECOND) do |client|
        api = client.create_write_api
        api.write(data: data)
      end
    end

    private

    def map(consumptions)
      consumptions.flat_map do |c|
        point = InfluxDB2::Point.new(name: c['service'])
                                .add_tag('unit-of-measure', c['unitOfMeasure'])
                                .add_tag('quality', c['quality'])
                                .add_tag('revision', c['revision'])
                                .add_tag('status', c['status'])
                                .add_field('amount', c['amount'])

        first = DateTime.new(*c['period'].split('-').map(&:to_i), 1)

        point.dup.time(first.to_time.to_i, InfluxDB2::WritePrecision::SECOND)
      end
    end
  end
end
