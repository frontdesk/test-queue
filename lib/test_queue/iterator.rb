module TestQueue
  class Iterator
    attr_reader :stats, :sock

    def initialize(sock, suites, filter=nil)
      @done = false
      @stats = {}
      @procline = $0
      @sock = sock
      @suites = suites
      @filter = filter
      if @sock =~ /^(.+):(\d+)$/
        @tcp_address = $1
        @tcp_port = $2.to_i
      end
      @redis = Redis.new :host => ENV['TEST_QUEUE_REDIS_HOST'], :port => (ENV['TEST_QUEUE_REDIS_PORT'] || '6379')
      @redis.auth ENV['TEST_QUEUE_REDIS_PASSWORD'] if ENV['TEST_QUEUE_REDIS_PASSWORD']
    end

    def each
      fail 'already used this iterator' if @done
      count = 0
      while true 
        count += 1
        data = @redis.lpop("test-queue:queue")
        break if data.nil?

        item = Marshal.load(data)                
        
        break if item.nil?
        suite = @suites[item.to_s]
        break if suite.nil?

        $0 = "#{@procline} - #{suite.respond_to?(:description) ? suite.description : suite}"
        start = Time.now
        if @filter
          @filter.call(suite){ yield suite }
        else
          yield suite
        end
        @stats[suite.to_s] = Time.now - start
      end
    rescue Errno::ENOENT, Errno::ECONNRESET, Errno::ECONNREFUSED
    ensure
      @done = true      
      File.open("/tmp/test_queue_worker_#{$$}_stats", "wb") do |f|
        f.write Marshal.dump(@stats)
      end
    end

    def connect_to_master(cmd)
      sock =
        if @tcp_address
          TCPSocket.new(@tcp_address, @tcp_port)
        else
          UNIXSocket.new(@sock)
        end
      sock.puts(cmd)
      sock
    end

    include Enumerable

    def empty?
      false
    end
  end
end
