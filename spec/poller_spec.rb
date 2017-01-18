# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
RSpec.describe MovidaEvents::Poller do
  let(:client) do
    instance_double(MovidaEvents::Client)
  end

  let(:options) { { interval: 0, newer_than: 5555 } }

  let(:poller) do
    described_class.new(client, options)
  end

  it 'starts polling after the last position' do
    options[:newer_than] = nil

    expect(client).to receive(:events)
      .with(no_args)
      .and_return([OpenStruct.new(id: 1234)].to_enum)
      .ordered

    expect(client).to receive(:events)
      .with(hash_including(newer_than: 1234))
      .ordered

    poller.poll(1)
  end

  it 'sends the last id to the client' do
    expect(client).to receive(:events)
      .with(hash_including(newer_than: 5555))

    poller.poll(1)
  end

  it 'allows setting the poll interval' do
    options[:interval] = 60

    expect(client).to receive(:events)
    expect(poller).to receive(:sleep).with(60)

    poller.poll(1)
  end

  it 'can set the allowed event types' do
    options[:event_types] = 'title_created,title_updated'

    expect(client).to receive(:events)
      .with(hash_including(event_type: 'title_created,title_updated'))

    poller.poll(1)
  end

  it 'can set the allowed event types with an array' do
    options[:event_types] = %w(title_created title_updated)

    expect(client).to receive(:events)
      .with(hash_including(event_type: 'title_created,title_updated'))
      .and_return([].to_enum)

    poller.poll(1)
  end

  it 'skips sleeping if events were received' do
    expect(client).to receive(:events) do |_opts, &block|
      block.call(OpenStruct.new(id: 4567))
    end.ordered

    expect(client).to receive(:events).ordered
    expect(poller).to receive(:sleep).once

    poller.poll(2)
  end

  it 'sends the events to poll block' do
    expect(client).to receive(:events) do |_opts, &block|
      block.call(OpenStruct.new(id: 4567))
    end.ordered

    polled = false
    poller.poll(1) do |event|
      polled = true
      expect(event.id).to eq(4567)
    end

    expect(polled).to eq(true)
  end

  it 'updates stats before first request' do
    expect(client).to receive(:events) do |_opts, &block|
      block.call(OpenStruct.new(id: 4567))
    end.ordered

    polled = false
    poller.poll(1) do |_event, stats|
      polled = true
      expect(stats.last).to eq(4567)
      expect(stats.requests).to eq(1)
      expect(stats.events).to eq(1)
      expect(stats.request_events).to eq(1)
    end

    expect(polled).to eq(true)
  end

  it 'updates stats for each event' do
    expect(client).to receive(:events) do |_opts, &block|
      block.call(OpenStruct.new(id: 100))
      block.call(OpenStruct.new(id: 200))
    end.ordered

    expect(client).to receive(:events) do |_opts, &block|
      block.call(OpenStruct.new(id: 300))
    end.ordered

    all_stats = []
    poller.poll(2) do |_event, stats|
      all_stats << stats
    end

    expect(all_stats.size).to eq(3)

    expect(all_stats[0].last).to eq(100)
    expect(all_stats[0].requests).to eq(1)
    expect(all_stats[0].events).to eq(1)
    expect(all_stats[0].request_events).to eq(1)

    expect(all_stats[1].last).to eq(200)
    expect(all_stats[1].requests).to eq(1)
    expect(all_stats[1].events).to eq(2)
    expect(all_stats[1].request_events).to eq(2)

    expect(all_stats[2].last).to eq(300)
    expect(all_stats[2].requests).to eq(2)
    expect(all_stats[2].events).to eq(3)
    expect(all_stats[2].request_events).to eq(1)
  end

  it 'calls on_poll before each request' do
    expect(client).to receive(:events) do |_opts, &block|
      block.call(OpenStruct.new(id: 100))
    end.ordered

    expect(client).to receive(:events) do |_opts, &block|
      block.call(OpenStruct.new(id: 200))
      block.call(OpenStruct.new(id: 300))
    end.ordered

    expect(client).to receive(:events).ordered

    all_stats = []
    poller.on_poll do |stats|
      all_stats << stats
    end

    poller.poll(3)

    expect(all_stats.map(&:last)).to eq([5555, 100, 300])
  end
end
