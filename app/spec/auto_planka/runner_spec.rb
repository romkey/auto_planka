# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AutoPlanka::Runner do
  let(:logger) { Logger.new(File::NULL) }
  let(:db) { instance_double(PG::Connection, close: nil) }
  let(:validator) { instance_double(AutoPlanka::SchemaValidator, validate!: true) }
  let(:syncer) { instance_double(AutoPlanka::Syncer, run_once: { memberships: 0, managers: 0, labels: 0 }) }
  let(:sleeps) { [] }
  let(:connections) { [] }

  let(:config) do
    AutoPlanka::Config.new(
      public_project_ids: ['1001'],
      database_url: 'postgres://example/planka',
      sleep_interval: 60,
      max_retries: 3
    )
  end

  before do
    allow(AutoPlanka::SchemaValidator).to receive(:new).and_return(validator)
    allow(AutoPlanka::Syncer).to receive(:new).and_return(syncer)
  end

  # Builds a runner whose clock and connection are under the test's control.
  # `stop_after` ends the loop once that many sleeps have elapsed.
  def build_runner(stop_after: nil)
    runner = nil
    sleeper = lambda do |seconds|
      sleeps << seconds
      runner.stop('TERM') if stop_after && sleeps.length >= stop_after
    end

    connector = lambda do
      connections << :connect
      db
    end

    runner = described_class.new(
      config,
      logger: logger,
      connector: connector,
      sleeper: sleeper,
      handle_signals: false
    )
  end

  describe 'the happy path' do
    it 'validates, syncs, and sleeps for the configured interval' do
      runner = build_runner(stop_after: 1)

      expect(runner.run).to eq(0)
      expect(validator).to have_received(:validate!).once
      expect(syncer).to have_received(:run_once).once
      expect(sleeps).to eq([60])
    end

    it 'reuses one connection and validates the schema only once' do
      runner = build_runner(stop_after: 3)

      runner.run

      expect(connections.length).to eq(1)
      expect(validator).to have_received(:validate!).once
      expect(syncer).to have_received(:run_once).exactly(3).times
    end

    it 'closes the connection on shutdown' do
      build_runner(stop_after: 1).run

      expect(db).to have_received(:close)
    end
  end

  describe 'an incompatible schema' do
    before { allow(validator).to receive(:validate!).and_raise(AutoPlanka::IncompatibleSchemaError, 'Planka v2+') }

    it 'exits non-zero without syncing' do
      runner = build_runner

      expect(runner.run).to eq(1)
      expect(syncer).not_to have_received(:run_once)
    end

    it 'does not retry' do
      build_runner.run

      expect(sleeps).to be_empty
    end
  end

  describe 'database errors' do
    it 'reconnects and backs off exponentially, then carries on' do
      attempts = 0
      allow(syncer).to receive(:run_once) do
        attempts += 1
        raise PG::Error, 'connection lost' if attempts <= 2

        { memberships: 0, managers: 0, labels: 0 }
      end

      runner = build_runner(stop_after: 3)

      expect(runner.run).to eq(0)
      expect(sleeps).to eq([2, 4, 60])
      expect(connections.length).to eq(3)
    end

    it 'gives up after max_retries' do
      allow(syncer).to receive(:run_once).and_raise(PG::Error, 'connection refused')

      runner = build_runner

      expect(runner.run).to eq(1)
      expect(syncer).to have_received(:run_once).exactly(3).times
      expect(sleeps).to eq([2, 4])
    end

    it 'resets the retry counter after a successful pass' do
      attempts = 0
      allow(syncer).to receive(:run_once) do
        attempts += 1
        raise PG::Error, 'blip' if [1, 3].include?(attempts)

        { memberships: 0, managers: 0, labels: 0 }
      end

      runner = build_runner(stop_after: 4)

      expect(runner.run).to eq(0)
      expect(sleeps).to eq([2, 60, 2, 60])
    end

    it 'revalidates the schema after reconnecting' do
      attempts = 0
      allow(syncer).to receive(:run_once) do
        attempts += 1
        raise PG::Error, 'connection lost' if attempts == 1

        { memberships: 0, managers: 0, labels: 0 }
      end

      build_runner(stop_after: 2).run

      expect(validator).to have_received(:validate!).twice
    end
  end

  describe '#stop' do
    it 'ends the loop before the next pass' do
      runner = build_runner(stop_after: 1)

      expect(runner.run).to eq(0)
      expect(syncer).to have_received(:run_once).once
    end
  end
end
