require 'redis_reliable_queue'
require 'thread'

redis = Redis.new
# Create a queue that will listen for a new element for 10 seconds
queue = Redis::ReliableQueue.new(redis: redis, timeout: 10)
queue.clear true

100.times { queue << rand(100) }

# Simulate a delayed insert
t = Thread.new do
  sleep 3
  # We should use a second connection here since the first one is busy
  # on a blocking call
  redis_in_thread = Redis.new
  queue_in_thread = Redis::ReliableQueue.new(redis: redis_in_thread)
  100.times { queue_in_thread << "e_#{rand(100)}" }
end

# When all elements are dequeud, process method will wait for 10 secods before exit
queue.process do |message|
  puts "'#{message}'"
end
t.join
