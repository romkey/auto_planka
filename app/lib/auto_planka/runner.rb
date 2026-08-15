# frozen_string_literal: true

require 'pg'

module AutoPlanka
  # Owns the long-running loop: connect, validate, sync, sleep, repeat.
  #
  # `connector` and `sleeper` are injectable so the loop can be exercised in
  # tests without a real database or real elapsed time.
  class Runner
    MAX_BACKOFF_SECONDS = 60
    SHUTDOWN_SIGNALS = %w[INT TERM].freeze

    def initialize(config, logger: AutoPlanka.logger, connector: nil, sleeper: nil, handle_signals: true)
      @config = config
      @logger = logger
      @connector = connector || -> { connect }
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @handle_signals = handle_signals
      @running = true
      @signal = nil
      @db = nil
      @schema_validated = false
      @retry_count = 0
    end

    # Returns the process exit status.
    def run
      install_signal_handlers if @handle_signals
      @logger.info("Syncing #{@config.public_project_ids.length} public project(s) " \
                   "every #{@config.sleep_interval}s")

      status = loop_until_stopped
      close_connection
      status
    end

    def stop(signal = nil)
      @signal = signal
      @running = false
    end

    private

    def loop_until_stopped
      while @running
        status = tick
        return status if status
      end

      @logger.info(@signal ? "Received SIG#{@signal}, shutting down" : 'Shutting down')
      0
    end

    # Runs one connect/validate/sync/sleep cycle. Returns nil to keep looping,
    # or an exit status to stop.
    def tick
      @db ||= @connector.call
      validate_schema unless @schema_validated

      syncer.run_once
      @retry_count = 0

      @sleeper.call(@config.sleep_interval) if @running
      nil
    rescue IncompatibleSchemaError => e
      @logger.fatal(e.message)
      1
    rescue PG::Error => e
      handle_database_error(e)
    end

    def connect
      @logger.info('Connecting to database...')
      db = PG.connect(@config.database_url)
      @logger.info('Connected to database')
      db
    end

    def validate_schema
      SchemaValidator.new(
        @db,
        logger: @logger,
        skip_version_check: @config.skip_version_check?
      ).validate!
      @schema_validated = true
    end

    def syncer
      Syncer.new(
        @db,
        public_project_ids: @config.public_project_ids,
        role: @config.role,
        logger: @logger
      )
    end

    def handle_database_error(error)
      @retry_count += 1
      @logger.error("Database error (attempt #{@retry_count}/#{@config.max_retries}): #{error.message}")

      close_connection
      @schema_validated = false

      if @retry_count >= @config.max_retries
        @logger.fatal('Giving up after too many database errors')
        return 1
      end

      return nil unless @running

      backoff = [2**@retry_count, MAX_BACKOFF_SECONDS].min
      @logger.info("Retrying in #{backoff} seconds...")
      @sleeper.call(backoff)
      nil
    end

    def close_connection
      @db&.close
    rescue PG::Error
      nil
    ensure
      @db = nil
    end

    # Traps must not log: Logger takes a mutex and Ruby raises
    # "can't be called from trap context" if it is already held.
    def install_signal_handlers
      SHUTDOWN_SIGNALS.each do |signal|
        Signal.trap(signal) { stop(signal) }
      end
    end
  end
end
