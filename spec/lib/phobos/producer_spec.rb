require 'spec_helper'

RSpec.describe Phobos::Producer do
  class TestProducer1
    include Phobos::Producer
  end

  before { TestProducer1.producer.configure_kafka_client(nil) }
  subject { TestProducer1.new }

  describe '#publish' do
    it 'publishes a single message using "publish_list"' do
      public_api = Phobos::Producer::PublicAPI.new(subject)
      allow(Phobos::Producer::PublicAPI).to receive(:new).and_return(public_api)

      expect(subject.producer)
        .to receive(:publish_list)
        .with([{ topic: 'topic', payload: 'message', key: 'key' }])

      subject.producer.publish('topic', 'message', 'key')
    end
  end

  describe '#async_publish' do
    it 'publishes a single message using "async_publish"' do
      public_api = Phobos::Producer::PublicAPI.new(subject)
      allow(Phobos::Producer::PublicAPI).to receive(:new).and_return(public_api)

      expect(subject.producer)
        .to receive(:async_publish_list)
        .with([{ topic: 'topic', payload: 'message', key: 'key' }])

      TestProducer1.producer.create_async_producer
      subject.producer.async_publish('topic', 'message', 'key')
    end
  end

  describe '#publish_list' do
    describe 'with a configured client' do
      let(:kafka_client) { double('Kafka::Client', producer: true, close: true) }
      let(:producer) { double('Kafka::NormalProducer', produce: true, deliver_messages: true) }

      before do
        TestProducer1.producer.configure_kafka_client(kafka_client)
        expect(Phobos).to_not receive(:create_kafka_client)
      end

      it 'publishes and deliver a list of messages but it does not close connection' do
        expect(kafka_client)
          .to receive(:producer)
          .with(Phobos.config.producer_hash)
          .and_return(producer)

        expect(producer)
          .to receive(:produce)
          .with('message-1', topic: 'topic-1', key: 'key-1', partition_key: 'key-1')

        expect(producer)
          .to receive(:produce)
          .with('message-2', topic: 'topic-2', key: 'key-2', partition_key: 'key-2')

        expect(producer).to receive(:deliver_messages)
        expect(producer).to_not receive(:close)

        subject.producer.publish_list([
          { payload: 'message-1', topic: 'topic-1', key: 'key-1' },
          { payload: 'message-2', topic: 'topic-2', key: 'key-2' }
        ])
      end
    end

    describe 'without a configured client' do
      let(:kafka_client) { double('Kafka::Client', producer: true, close: true) }
      let(:producer) { double('Kafka::NormalProducer', produce: true, deliver_messages: true) }

      it 'publishes a list of messages, deliver and closes the connection right away' do
        expect(Phobos).to receive(:create_kafka_client).and_return(kafka_client)

        expect(kafka_client)
          .to receive(:producer)
          .with(Phobos.config.producer_hash)
          .and_return(producer)

        expect(producer)
          .to receive(:produce)
          .with('message-1', topic: 'topic-1', key: 'key-1', partition_key: 'key-1')

        expect(producer)
          .to receive(:produce)
          .with('message-2', topic: 'topic-2', key: 'key-2', partition_key: 'key-2')

        expect(producer).to receive(:deliver_messages)
        expect(kafka_client).to receive(:close)

        subject.producer.publish_list([
          { payload: 'message-1', topic: 'topic-1', key: 'key-1' },
          { payload: 'message-2', topic: 'topic-2', key: 'key-2' }
        ])
      end
    end
  end

  describe '#async_publish_list' do
    describe 'with a configured async_producer' do
      let(:kafka_client) { double('Kafka::Client', producer: true, close: true) }
      let(:producer) { double('Kafka::AsyncProducer', produce: true, deliver_messages: true) }

      before do
        allow(kafka_client).to receive(:async_producer).and_return(producer)
      end

      it 'publishes and deliver a list of messages without closing the connection' do
        expect(producer)
          .to receive(:produce)
          .with('message-1', topic: 'topic-1', key: 'key-1', partition_key: 'key-1')

        expect(producer)
          .to receive(:produce)
          .with('message-2', topic: 'topic-2', key: 'key-2', partition_key: 'key-2')

        expect(producer).to receive(:deliver_messages)
        expect(producer).to_not receive(:close)

        Thread.new do
          TestProducer1.producer.configure_kafka_client(kafka_client)
          TestProducer1.producer.create_async_producer

          subject.producer.async_publish_list([
            { payload: 'message-1', topic: 'topic-1', key: 'key-1' },
            { payload: 'message-2', topic: 'topic-2', key: 'key-2' }
          ])
        end.join
      end
    end

    describe 'without a configured async_producer' do
      it 'raises Phobos::AsyncProducerNotConfiguredError' do
        expect do
          subject.producer.async_publish_list([])
        end.to raise_error(Phobos::AsyncProducerNotConfiguredError)
      end
    end
  end

  describe '.configure_kafka_client' do
    it 'configures kafka client to the class bound to the current thread' do
      results = Concurrent::Array.new
      latch = Concurrent::CountDownLatch.new(2)

      t1 = Thread.new do
        TestProducer1.producer.configure_kafka_client(:kafka1)
        latch.count_down
        results << TestProducer1.producer.kafka_client
      end

      t2 = Thread.new do
        TestProducer1.producer.configure_kafka_client(:kafka2)
        latch.count_down
        results << TestProducer1.producer.kafka_client
      end

      t3 = Thread.new do
        latch.wait
        expect(TestProducer1.producer.kafka_client).to be_nil
      end

      [t1, t2, t3].map(&:join)
      expect(results.first).to_not eql results.last
    end
  end

  describe '.create_async_producer' do
    let(:kafka_client) { double('Kafka::Client', async_producer: true) }

    describe 'without a kafka_client configured' do
      it 'creates a new client and an async_producer bound to the current thread' do
        expect(kafka_client)
          .to receive(:async_producer)
          .with(Phobos.config.producer_hash)
          .and_return(:async1, :async2)

        expect(Phobos)
          .to receive(:create_kafka_client)
          .twice
          .and_return(kafka_client)

        results = Concurrent::Array.new
        latch = Concurrent::CountDownLatch.new(2)

        t1 = Thread.new do
          expect(TestProducer1.producer.kafka_client).to be_nil
          expect(TestProducer1.producer.async_producer).to be_nil

          TestProducer1.producer.create_async_producer
          expect(TestProducer1.producer.kafka_client).to eql kafka_client

          latch.count_down
          results << TestProducer1.producer.async_producer
        end

        t2 = Thread.new do
          expect(TestProducer1.producer.kafka_client).to be_nil
          expect(TestProducer1.producer.async_producer).to be_nil

          TestProducer1.producer.create_async_producer
          expect(TestProducer1.producer.kafka_client).to eql kafka_client

          latch.count_down
          results << TestProducer1.producer.async_producer
        end

        t3 = Thread.new do
          latch.wait
          expect(TestProducer1.producer.async_producer).to be_nil
        end

        [t1, t2, t3].map(&:join)
        expect(results.first).to_not eql results.last
      end
    end

    describe 'with a kafka_client configured' do
      it 'uses the configured client' do
        expect(Phobos).to_not receive(:create_kafka_client)
        Thread.new do
          TestProducer1.producer.configure_kafka_client(kafka_client)
          TestProducer1.producer.create_async_producer
        end.join
      end
    end
  end

  describe '.async_producer_shutdown' do
    let(:async_producer) { double('Kafka::AsyncProducer', deliver_messages: true, shutdown: true) }
    let(:kafka_client) { double('Kafka::Client', async_producer: async_producer) }

    it 'calls deliver_messages and shutdown in the configured client and cleans up producer' do
      expect(async_producer).to receive(:deliver_messages)
      expect(async_producer).to receive(:shutdown)

      Thread.new do
        TestProducer1.producer.configure_kafka_client(kafka_client)

        TestProducer1.producer.create_async_producer
        expect(TestProducer1.producer.async_producer).to_not be_nil

        TestProducer1.producer.async_producer_shutdown
        expect(TestProducer1.producer.async_producer).to be_nil
      end.join
    end
  end
end