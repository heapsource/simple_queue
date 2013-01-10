begin
  require "rubinius/actor"
rescue RuntimeError
  require "simple_queue/actor"
end
require "case"
require "redis"

class SimpleQueue
  FinishedWork = Case::Struct.new(:worker, :job)
  Work = Case::Struct.new(:job)

  def self.redis
    @@redis ||= Redis.new
  end

  def self.redis=(redis)
    @@redis = redis
  end

  class Consumer
    attr_accessor :active_workers, :inactive_workers, :workers, :queue

    def initialize(queue, workers = 20)
      @queue = Queue.new(queue)
      @inactive_workers = nil
      @active_workers = []
      @workers = workers
    end

    def start
      trap("INT") { stop }

      @supervisor = Rubinius::Actor.spawn do
        Rubinius::Actor.trap_exit = true
        begin
          supervisor_loop
        rescue Exception => error
          $stderr.puts "Error in supervisor loop"
          $stderr.puts "Exception: #{error}: \n#{error.backtrace.join("\n")}"
        end
      end

      puts "Starting to consume jobs in '#{@queue.name}' queue..."
      wait_queue_loop
    end

    def stop
      puts "Stopping consuming jobs in '#{@queue.name}' queue"
      @stopping = true
    end

    def inactive_workers
      @inactive_workers ||= Array.new(@workers) { Rubinius::Actor.spawn_link(&method(:work_loop)) }
    end

    private

    def supervisor_loop
      loop do
        case message = Rubinius::Actor.receive
        when Work
          worker = inactive_workers.pop
          puts "Work received, sending work to Worker (#{worker.object_id})"
          active_workers << worker
          worker << message
        when FinishedWork
          worker = message.worker
          @queue.recycle(message.job)
          puts "Finished Work received, sending to Worker (#{worker.object_id}) to inactive workers"
          inactive_workers << worker
          active_workers.delete(worker)
        when Rubinius::Actor::DeadActorError
          $stderr.puts "Actor exited with message: #{message.reason}"
          inactive_workers << Rubinius::Actor.spawn_link(&method(:work_loop))
        end
      end
    end

    def work_loop
      loop do
        case message = Rubinius::Actor.receive
        when Work
          job = Marshal.load(message.job)
          job.run
          @supervisor << FinishedWork[Rubinius::Actor.current, message.job]
        end
      end
    end

    def wait_queue_loop
      loop do
        break if @stopping
        job = @queue.pop
        next unless job
        puts "New job received, sending work to Supervisor (#{@supervisor.object_id})"
        @supervisor << Work[job]
      end
    end
  end

  class Queue
    attr_reader :name

    def initialize(name)
      @name = name
      @backup = "simple:#{@name}:#{Socket.gethostname}:#{Process.pid}"
      puts "Jobs backups will be saved in #{@backup}"
    end

    def push(job)
      SimpleQueue.redis.lpush("simple:#{@name}", Marshal.dump(job))
    end

    def pop
      SimpleQueue.redis.brpoplpush("simple:#{@name}", @backup, 1)
    end

    def recycle(job)
      SimpleQueue.redis.lrem(@backup, 1, job)
    end

    def size
      SimpleQueue.redis.llen("simple:#{@name}")
    end
  end
end
