require "securerandom"
require "rubinius/actor"
require "case"
require "redis"

class SimpleQueue
  FinishedWork = Case::Struct.new(:worker, :job_id, :result)
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

      puts "Starting to consume jobs in #{@queue} queue..."
      wait_queue_loop
    end

    def stop
      puts "Stopping consuming jobs in #{@queue} queue"
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
          queue.notify(@queue.name, message.job_id, "finished", message.result) if queue.respond_to?(:notify)
          worker = message.worker
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
          job_id, job = Marshal.load(message.job)
          result = Marshal.dump(job.run)
          @supervisor << FinishedWork[Rubinius::Actor.current, job_id, result]
        end
      end
    end

    def wait_queue_loop
      loop do
        break if @stopping
        if job = @queue.pop
          puts "New job received, sending work to Supervisor (#{@supervisor.object_id})"
          @supervisor << Work[job]
        end
      end
    end
  end

  class Queue < Struct.new(:name)
    def push(job)
      job_id = SecureRandom.hex(8)
      SimpleQueue.redis.lpush("simple:#{@name}", Marshal.dump([job_id, job]))
      SimpleQueue.redis.mapped_hmset("simple:#{@name}:#{job_id}", :status => "pending", :result => nil)
      job_id
    end

    def pop
      SimpleQueue.redis.rpop("simple:#{@name}")
    end

    def status(job_id)
      SimpleQueue.redis.mapped_hmget("simple:#{@name}:#{job_id}", "status", "result")
    end

    def size
      SimpleQueue.redis.llen("simple:#{@name}")
    end

    def notify(queue_name, job_id, status, result)
      SimpleQueue.redis.mapped_hmset("simple:#{queue_name}:#{job_id}", :status => status, :result => result)
    end
  end
end
