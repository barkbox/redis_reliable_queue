require 'spec_helper'
require 'timeout'
require 'pry'

describe Redis::ReliableQueue do
  before(:all) do
    @redis = Redis.new
    @queue = Redis::ReliableQueue.new
    @queue.clear true
  end

  after(:all) do
    @queue.clear true
  end

  it 'should return correct version string' do
    Redis::ReliableQueue.version.should == "redis-queue version #{Redis::ReliableQueue::VERSION}"
  end

  it 'should create a new redis-queue object' do
    queue = Redis::ReliableQueue.new
    queue.class.should == Redis::ReliableQueue
  end

  it 'should return an explicitly assigned queue name' do
    queue_name = 'qqq'
    queue = Redis::ReliableQueue.new(queue_name: queue_name)
    queue.waiting.should be == queue_name
  end

  context 'should be possible to have two instances working with the same queue' do
    before(:each) do
      queue_name = 'qqq'
      @queue1 = Redis::ReliableQueue.new(queue_name: queue_name)
      @queue2 = Redis::ReliableQueue.new(queue_name: queue_name)
    end

    after(:each) do
      [@queue1, @queue2].each { |q| q.clear true }
    end

    it 'should create two different instances' do
      @queue1.should_not be eql @queue2
    end

    it 'should have the same name for waiting queues' do
      @queue1.waiting.should be == @queue2.waiting
    end

    it 'should be possible to exchange data between the instances' do
      payload = 'a'
      @queue1 << payload
      message = @queue2.pop(true)

      message.should be == payload
    end
  end

  it 'should add an element to the queue' do
    @queue << 'a'
    @queue.size.should be == 1
  end

  it 'should return an element from the queue' do
    message = @queue.pop(true)
    message.should be == 'a'
  end

  it 'should remove the element from processing queue if commit is called' do
    @redis.llen(@queue.processing).should be == 1
    @queue.commit
    @redis.llen(@queue.processing).should be == 0
  end

  it 'should implements fifo pattern' do
    @queue.clear
    payload = %w(a b c d e)
    payload.each { |e| @queue << e }
    test = []
    while e = @queue.pop(true)
      test << e
    end
    payload.should be == test
  end

  it 'should remove all of the elements from the waiting queue' do
    %w(a b c d e).each { |e| @queue << e }
    @queue.size.should be > 0
    @queue.pop(true)
    @queue.clear
    @redis.llen(@queue.processing).should be > 0
  end

  it 'should reset queues content' do
    @queue.clear(true)
    @redis.llen(@queue.processing).should be == 0
  end

  it 'should prcess a message' do
    @queue << 'a'
    @queue.process(true) { |m| m.should be == 'a'; true }
  end

  it 'should prcess a message leaving it into the processing queue' do
    payload = %w(a a)
    serialized_payload = payload.map { |e| Marshal.dump(e) }
    payload.each { |p| @queue << p }

    @queue.process(true) { |m| m.should be == 'a'; false }
    @redis.lrange(@queue.processing, 0, -1).should be == serialized_payload
  end

  it 'should refill the waiting queue' do
    payload = %w(a a)
    serialized_payload = payload.map { |e| Marshal.dump(e) }

    @queue.clear(true)
    payload.each { |p| @queue << p }

    @queue.process(true) { |m| m.should be == 'a'; false }
    @redis.lrange(@queue.processing, 0, -1).should be == serialized_payload
    @queue.refill
    @redis.lrange(@queue.waiting, 0, -1).should be == serialized_payload
    @redis.llen(@queue.processing).should be == 0
  end

  it 'should work with the timeout parameters' do
    @queue.clear(true)
    2.times { @queue << rand(100) }
    is_ok = true
    begin
      Timeout::timeout(3) do
        @queue.process(false, 2) { |m| true }
      end
    rescue Timeout::Error => e
      is_ok = false
    end

    is_ok.should be true
  end

  it 'should work with a maximum count' do
    @queue.clear(true)
    @queue << 'a'
    @queue << 'b'
    @queue.process(true, nil, 1) { |m| m.should be == 'a'; true }
    @queue.process(true, nil, 1) { |m| m.should be == 'b'; true }
    @queue.process(true, nil, 1) { |m| m.should be == nil; true }
  end

  it 'should work with a maximum count with a negative number' do
    @queue.clear(true)
    @queue << 'a'
    @queue << 'b'
    @queue.process(true, nil, -1) { |m| m.should be == nil}
    expectations = ['a', 'b', nil]
    iteration = 0
    @queue.process(true, nil, 4) do |m|
      iteration.should be < 3
      m.should be == expectations[iteration]
      iteration += 1
    end
  end

  it 'should honor the timeout param in the initializer' do
    redis = Redis.new
    queue = Redis::ReliableQueue.new(redis: redis, timeout: 2)
    queue.clear true

    is_ok = true
    begin
      Timeout::timeout(4) do
        queue.pop
      end
    rescue Timeout::Error => e
      is_ok = false
    end
    queue.clear
    is_ok.should be true
  end
end
