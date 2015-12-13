require 'redis_reliable_queue'

redis = Redis.new

queue = Redis::ReliableQueue.new(redis: redis)
queue.clear true

100.times { queue << rand(100) }

queue.process(true) { |m| puts m }
