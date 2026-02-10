# frozen_string_literal: true

class Wait
  INTERVAL = 0.1
  TIMEOUT = 30

  class << self
    def until(timeout: TIMEOUT, interval: INTERVAL)
      end_time = ::Time.now + timeout

      until ::Time.now > end_time
        result = yield(self)
        return result if result

        sleep(interval)
      end

      raise "Timeout after waiting for #{timeout} seconds"
    end
  end
end
