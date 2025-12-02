#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pg'
require 'json'
require 'logger'
require 'dotenv/load'

# Configuration constants from environment
SLEEP_INTERVAL = ENV.fetch('SLEEP_INTERVAL', 60).to_i
DEFAULT_ROLE = ENV.fetch('DEFAULT_ROLE', 'editor')
LOG_LEVEL = ENV.fetch('LOG_LEVEL', 'INFO')

# Set up logger
LOGGER = Logger.new($stdout)
LOGGER.level = Logger.const_get(LOG_LEVEL)
LOGGER.formatter = proc do |severity, datetime, _progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

class AutoPlanka
  def initialize(config, db)
    @config = config
    @db = db
  end

  def run_once
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')
    public_board_ids = get_public_board_ids

    if public_board_ids.empty?
      LOGGER.warn('No public boards found for configured project IDs')
      return
    end

    @db.transaction do
      make_projects_public(timestamp, public_board_ids)
      LOGGER.info('Made projects public')

      make_admins_public_project_managers(timestamp)
      LOGGER.info('Made admins managers')

      make_labels_public(timestamp, public_board_ids)
      LOGGER.info('Propagated labels')
    end
  rescue PG::Error => e
    LOGGER.error("Database error during run: #{e.message}")
    raise
  end

  private

  def escape(value)
    PG::Connection.escape_string(value.to_s)
  end

  def to_sql_list(array)
    array.map { |elt| "'#{escape(elt)}'" }.join(',')
  end

  def get_public_board_ids
    return [] if @config[:public_project_ids].nil? || @config[:public_project_ids].empty?

    query = "SELECT id FROM board WHERE project_id IN (#{to_sql_list(@config[:public_project_ids])})"
    @db.exec(query).map { |board| board['id'] }
  end

  # Make boards public by adding all users as board members
  def make_projects_public(timestamp, public_board_ids)
    users = @db.exec('SELECT id FROM user_account WHERE deleted_at IS NULL')
    return if users.ntuples.zero?

    values = []
    public_board_ids.each do |board_id|
      users.each do |user|
        values << "(next_id(), '#{escape(board_id)}', '#{escape(user['id'])}', " \
                  "'#{escape(timestamp)}', NULL, '#{escape(DEFAULT_ROLE)}', NULL)"
      end
    end

    return if values.empty?

    @db.exec("INSERT INTO board_membership (id, board_id, user_id, created_at, updated_at, role, can_comment) " \
             "VALUES #{values.join(',')} ON CONFLICT DO NOTHING")
  end

  # Propagate labels across all public boards
  def make_labels_public(timestamp, public_board_ids)
    return if public_board_ids.empty?

    labels = @db.exec(
      "SELECT DISTINCT ON (name) name, color, position FROM label " \
      "WHERE board_id IN (#{to_sql_list(public_board_ids)}) ORDER BY name, created_at"
    )
    return if labels.ntuples.zero?

    values = []
    labels.each do |label|
      public_board_ids.each do |board_id|
        values << "(next_id(), '#{escape(board_id)}', '#{escape(label['name'])}', " \
                  "'#{escape(label['color'])}', '#{escape(timestamp)}', NULL, '#{escape(label['position'])}')"
      end
    end

    return if values.empty?

    @db.exec("INSERT INTO label (id, board_id, name, color, created_at, updated_at, position) " \
             "VALUES #{values.join(',')} ON CONFLICT DO NOTHING")
  end

  # Make all Planka admins managers on public projects
  def make_admins_public_project_managers(timestamp)
    admins = @db.exec("SELECT id FROM user_account WHERE is_admin = 't' AND deleted_at IS NULL")
    return if admins.ntuples.zero?

    values = []
    @config[:public_project_ids].each do |project_id|
      admins.each do |admin|
        values << "(next_id(), '#{escape(project_id)}', '#{escape(admin['id'])}', " \
                  "'#{escape(timestamp)}', NULL)"
      end
    end

    return if values.empty?

    @db.exec("INSERT INTO project_manager (id, project_id, user_id, created_at, updated_at) " \
             "VALUES #{values.join(',')} ON CONFLICT DO NOTHING")
  end
end

def load_config
  config_path = ENV.fetch('CONFIG_PATH', 'config.json')

  unless File.exist?(config_path)
    LOGGER.fatal("Config file not found: #{config_path}")
    exit(1)
  end

  config = JSON.parse(File.read(config_path), symbolize_names: true)

  unless config[:public_project_ids].is_a?(Array) && config[:public_project_ids].any?
    LOGGER.fatal("Config must contain non-empty 'public_project_ids' array")
    exit(1)
  end

  LOGGER.info("Loaded config with #{config[:public_project_ids].length} public project(s)")
  config
rescue JSON::ParserError => e
  LOGGER.fatal("Invalid JSON in config file: #{e.message}")
  exit(1)
end

def connect_database
  connection_string = ENV['POSTGRESQL']

  if connection_string.nil? || connection_string.empty?
    LOGGER.fatal('POSTGRESQL environment variable not set')
    exit(1)
  end

  LOGGER.info('Connecting to database...')
  db = PG.connect(connection_string)
  LOGGER.info('Connected to database')
  db
rescue PG::Error => e
  LOGGER.error("Failed to connect to database: #{e.message}")
  raise
end

def main
  config = load_config

  # Set up graceful shutdown
  running = true
  Signal.trap('INT') do
    LOGGER.info('Received SIGINT, shutting down...')
    running = false
  end
  Signal.trap('TERM') do
    LOGGER.info('Received SIGTERM, shutting down...')
    running = false
  end

  db = nil
  retry_count = 0
  max_retries = 5

  while running
    begin
      db ||= connect_database
      retry_count = 0

      auto_planka = AutoPlanka.new(config, db)
      auto_planka.run_once

      LOGGER.debug("Sleeping for #{SLEEP_INTERVAL} seconds...")
      sleep(SLEEP_INTERVAL)
    rescue PG::Error => e
      retry_count += 1
      LOGGER.error("Database error (attempt #{retry_count}/#{max_retries}): #{e.message}")

      db&.close
      db = nil

      if retry_count >= max_retries
        LOGGER.fatal('Max retries exceeded, exiting')
        exit(1)
      end

      sleep_time = [2**retry_count, 60].min
      LOGGER.info("Retrying in #{sleep_time} seconds...")
      sleep(sleep_time)
    end
  end

  LOGGER.info('Shutting down gracefully')
  db&.close
end

main if __FILE__ == $PROGRAM_NAME
