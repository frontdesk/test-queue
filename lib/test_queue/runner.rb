require 'socket'
require 'fileutils'
require 'redis'
module TestQueue
  class Worker
    attr_accessor :pid, :status, :output, :stats, :num, :host
    attr_accessor :start_time, :end_time
    attr_accessor :summary, :failure_output

    def initialize(pid, num)
      @pid = pid
      @num = num
      @start_time = Time.now
      @output = ''
      @stats = {}
    end

    def lines
      @output.split("\n")
    end
  end

  class Runner
    attr_accessor :concurrency

    def initialize(queue, concurrency=nil, socket=nil, relay=nil)
      raise ArgumentError, 'array required' unless Array === queue
      abort "TEST_QUEUE_REDIS_HOST not set" unless ENV['TEST_QUEUE_REDIS_HOST']

      if forced = ENV['TEST_QUEUE_FORCE']
        forced = forced.split(/\s*,\s*/)
        whitelist = Set.new(forced)
        queue = queue.select{ |s| whitelist.include?(s.to_s) }
        queue.sort_by!{ |s| forced.index(s.to_s) }
      end

      if rerun = ENV['TEST_QUEUE_RETRY']
        queue = fetch_and_clear_failed_queue!
      end

      @procline = $0
      @queue = queue
      @suites = queue.inject(Hash.new){ |hash, suite| hash.update suite.to_s => suite }

      @workers = {}
      @completed = []

      @concurrency =
        concurrency ||
        (ENV['TEST_QUEUE_WORKERS'] && ENV['TEST_QUEUE_WORKERS'].to_i) ||
        if File.exists?('/proc/cpuinfo')
          File.read('/proc/cpuinfo').split("\n").grep(/processor/).size
        elsif RUBY_PLATFORM =~ /darwin/
          `/usr/sbin/sysctl -n hw.activecpu`.to_i
        else
          2
        end

      @socket =
        socket ||
        ENV['TEST_QUEUE_SOCKET'] ||
        "/tmp/test_queue_#{$$}_#{object_id}.sock"

      @relay =
        relay ||
        ENV['TEST_QUEUE_RELAY']

      if @relay == @socket
        STDERR.puts "*** Detected TEST_QUEUE_RELAY == TEST_QUEUE_SOCKET. Disabling relay mode."
        @relay = nil
      elsif @relay
        @queue = []
      end
    end

    def stats
      @stats ||=
        if File.exists?(file = stats_file)
          Marshal.load(IO.binread(file)) || {}
        else
          {}
        end
    end

    def execute
      $stdout.sync = $stderr.sync = true
      @start_time = Time.now

      @concurrency > 0 ?
        execute_parallel :
        execute_sequential
    ensure
      summarize_internal unless $!
    end

    def summarize_internal
      puts
      puts "==> Summary (#{@completed.size} workers in %.4fs)" % (Time.now-@start_time)
      puts

      @failures = ''
      @completed.each do |worker|
        summarize_worker(worker)
        @failures << worker.failure_output if worker.failure_output

        puts "    [%2d] %60s      %4d suites in %.4fs      (pid %d exit %d%s)" % [
          worker.num,
          worker.summary,
          worker.stats.size,
          worker.end_time - worker.start_time,
          worker.pid.to_i,
          worker.status.exitstatus.to_i,
          worker.host && " on #{worker.host.split('.').first}"
        ]
      end

      unless @failures.empty?
        puts
        puts "==> Failures"
        puts
        puts @failures.force_encoding("UTF-8")
      end

      puts

      if @stats
        File.open(stats_file, 'wb') do |f|
          f.write Marshal.dump(stats)
        end
      end

      summarize

      estatus = @completed.inject(0){ |s, worker| s + worker.status.exitstatus }
      estatus = 255 if estatus > 255
      exit!(estatus)
    end

    def summarize
    end

    def stats_file
      ENV['TEST_QUEUE_STATS'] ||
      '.test_queue_stats'
    end

    def execute_sequential
      exit! run_worker(@queue)
    end

    def execute_parallel
      start_master
      prepare(@concurrency)
      @prepared_time = Time.now
      # start_relay if relay?
      load_queue
      spawn_workers
      distribute_queue
    ensure
      stop_master

      @workers.each do |pid, worker|
        Process.kill 'KILL', pid
      end

      until @workers.empty?
        reap_worker
      end
    end

    def start_master
      puts "Starting master"
      @redis_proc = Proc.new {
        r = Redis.new :host => ENV['TEST_QUEUE_REDIS_HOST'], :port => (ENV['TEST_QUEUE_REDIS_PORT'] || '6379')
        r.auth ENV['TEST_QUEUE_REDIS_PASSWORD'] if ENV['TEST_QUEUE_REDIS_PASSWORD']
        r
      }
      @redis = Redis::Retry.new(:tries => 5, :wait => 5, :redis_proc => @redis_proc)
      if relay?
        begin
          remote_worker_incr @concurrency
        rescue Errno::ECONNREFUSED
          STDERR.puts "*** Unable to connect to relay #{@relay}. Aborting.."
          exit! 1
        end
      end

      desc = "test-queue master (#{relay?? "relaying to #{@relay}" : @socket})"
      puts "Starting #{desc}"
      $0 = "#{desc} - #{@procline}"
    end

    def start_relay
      return unless relay?

      # sock = connect_to_relay
      # sock.puts("SLAVE #{@concurrency} #{Socket.gethostname}")
      # sock.close
    rescue Errno::ECONNREFUSED
      STDERR.puts "*** Unable to connect to relay #{@relay}. Aborting.."
      exit! 1
    end

    def stop_master
      return if relay?

      FileUtils.rm_f(@socket) if @socket && @server.is_a?(UNIXServer)
      @server.close rescue nil if @server
      @socket = @server = nil
    end

    def spawn_workers
      @concurrency.times do |i|
        num = i+1

        pid = fork do
          iterator = Iterator.new(relay?? @relay : @socket, @suites, method(:around_filter))
          after_fork_internal(num, iterator)
          ret = run_worker(iterator) || 0
          cleanup_worker
          exit! ret
        end

        @workers[pid] = Worker.new(pid, num)
      end
    end

    def after_fork_internal(num, iterator)
      srand

      output = File.open("/tmp/test_queue_worker_#{$$}_output", 'w')

      $stdout.reopen(output)
      $stderr.reopen($stdout)
      $stdout.sync = $stderr.sync = true

      $0 = "test-queue worker [#{num}]"
      puts
      puts "==> Starting #$0 (#{Process.pid} on #{Socket.gethostname}) - iterating over #{iterator.sock}"
      puts

      after_fork(num)
    end

    def prepare(concurrency)
    end

    def around_filter(suite)
      yield
    end

    def after_fork(num)
    end

    def run_worker(iterator)
      iterator.each do |item|
        puts "  #{item.inspect}"
      end

      return 0 # exit status
    end

    def cleanup_worker
    end

    def summarize_worker(worker)
      worker.summary = ''
      worker.failure_output = ''
    end

    def reap_worker(blocking=true)
      if pid = Process.waitpid(-1, blocking ? 0 : Process::WNOHANG) and worker = @workers.delete(pid)
        begin
          worker.status = $?
          worker.end_time = Time.now

          if File.exists?(file = "/tmp/test_queue_worker_#{pid}_output")
            worker.output = IO.binread(file)
            FileUtils.rm(file)
          end

          if File.exists?(file = "/tmp/test_queue_worker_#{pid}_stats")
            worker.stats = Marshal.load(IO.binread(file))
            FileUtils.rm(file)
          end
        ensure
          relay_to_master(worker) if relay?
          worker_completed(worker)
        end
      end
    end

    def worker_completed(worker)
      @completed << worker
      puts worker.output.force_encoding("UTF-8") if ENV['TEST_QUEUE_VERBOSE'] || worker.status.exitstatus != 0
    end

    def queue_empty?
      @redis.llen('test-queue:queue') == 0 && @redis.llen('test-queue:workers') == 0
    end

    def remote_worker_count
      @redis.get('test-queue:remote_worker_count').to_i
    end

    def remote_worker_incr(count = 1)
      c = @redis.incrby 'test-queue:remote_worker_count', count.to_i
      @redis.set 'log', "count: #{c}"
    end

    def remote_worker_decr
      @redis.decr 'test-queue:remote_worker_count'
    end

    def fetch_and_clear_failed_queue!
      fq = @redis.lrange('test-queue:queue:failures', 0, -1).to_a
      puts "Retrying #{@redis.llen('test-queue:queue:failures')} suites..."
      @redis.del('test-queue:queue:failures')
      fq
    end

    def load_queue
      return if relay?
      @redis.del 'test-queue:remote_worker_count'
      @redis.del 'test-queue:queue'

      res = @redis.rpush 'test-queue:queue', @queue.map {|q| Marshal.dump(q.to_s) }
      puts "Loaded #{res} suites"
    end

    def distribute_queue
      return if relay?
      while true
        data = @redis.lpop('test-queue:workers')
        if data
          worker = Marshal.load(data)
          worker_completed(worker)
        end
        if queue_empty? && remote_worker_count == 0
          break
        end
        sleep 1
      end
    ensure
      stop_master

      until @workers.empty?
        reap_worker
      end
    end

    def relay?
      !!@relay
    end

    def connect_to_relay
      TCPSocket.new(*@relay.split(':'))
    end

    def relay_to_master(worker)
      worker.host = Socket.gethostname
      data = Marshal.dump(worker)

      # sock = connect_to_relay
      # sock.puts("WORKER #{data.bytesize}")
      # sock.write(data)
      @redis.rpush "test-queue:workers", data

    ensure
      remote_worker_decr
      # sock.close if sock
    end
  end
end
