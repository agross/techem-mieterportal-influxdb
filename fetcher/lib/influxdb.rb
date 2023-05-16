require 'influxdb-client'

class InfluxDb
  include InfluxDB2

  def self.store(address, token, org, bucket, consumptions)
    data = consumptions.flat_map do |c|
      point = Point.new(name: c['service'])
                   .add_tag('unit-of-measure', c['unitOfMeasure'])
                   .add_tag('quality', c['quality'])
                   .add_tag('revision', c['revision'])
                   .add_tag('status', c['status'])
                   .add_field('amount', c['amount'])

      first = DateTime.new(*c['period'].split('-').map(&:to_i), 1)

      point.dup.time(first.to_time.to_i, WritePrecision::SECOND)
    end

    Client.use(address,
      token,
      use_ssl: false,
      org: org,
      bucket: bucket,
      debugging: true,
      precision: WritePrecision::SECOND) do |client|
        api = client.create_write_api
        api.write(data: data)
    end
  end
end
