# frozen_string_literal: true

require 'json'

module AutoPlanka
  # Runtime settings, assembled from the environment and the JSON config file.
  class Config
    DEFAULT_CONFIG_PATH = 'config.json'
    DEFAULT_ROLE = 'editor'
    DEFAULT_SLEEP_INTERVAL = 60
    DEFAULT_MAX_RETRIES = 5
    VALID_ROLES = %w[editor viewer].freeze

    attr_reader :public_project_ids, :database_url, :role, :sleep_interval, :max_retries

    def self.from_env(env = ENV)
      path = env.fetch('CONFIG_PATH', DEFAULT_CONFIG_PATH)

      new(
        public_project_ids: read_project_ids(path),
        database_url: env['POSTGRESQL'],
        role: env.fetch('DEFAULT_ROLE', DEFAULT_ROLE),
        sleep_interval: env.fetch('SLEEP_INTERVAL', DEFAULT_SLEEP_INTERVAL).to_i,
        max_retries: env.fetch('MAX_RETRIES', DEFAULT_MAX_RETRIES).to_i,
        skip_version_check: env['SKIP_VERSION_CHECK'] == '1'
      )
    end

    def self.read_project_ids(path)
      raise ConfigError, "Config file not found: #{path}" unless File.exist?(path)

      parsed = JSON.parse(File.read(path), symbolize_names: true)
      parsed[:public_project_ids]
    rescue JSON::ParserError => e
      raise ConfigError, "Invalid JSON in #{path}: #{e.message}"
    end
    private_class_method :read_project_ids

    def initialize(public_project_ids:, database_url:, role: DEFAULT_ROLE,
                   sleep_interval: DEFAULT_SLEEP_INTERVAL, max_retries: DEFAULT_MAX_RETRIES,
                   skip_version_check: false)
      @public_project_ids = Array(public_project_ids).map(&:to_s)
      @database_url = database_url
      @role = role
      @sleep_interval = sleep_interval
      @max_retries = max_retries
      @skip_version_check = skip_version_check

      validate!
    end

    def skip_version_check?
      @skip_version_check
    end

    private

    def validate!
      validate_project_ids!
      validate_database_url!
      validate_role!
      validate_limits!
    end

    def validate_project_ids!
      raise ConfigError, "Config must contain a non-empty 'public_project_ids' array" if @public_project_ids.empty?

      malformed = @public_project_ids.grep_v(/\A\d+\z/)
      return if malformed.empty?

      raise ConfigError, "public_project_ids must be numeric Planka IDs, got: #{malformed.join(', ')}"
    end

    def validate_database_url!
      return unless @database_url.nil? || @database_url.empty?

      raise ConfigError, 'POSTGRESQL environment variable is not set'
    end

    def validate_role!
      return if VALID_ROLES.include?(@role)

      raise ConfigError, "DEFAULT_ROLE must be one of: #{VALID_ROLES.join(', ')}"
    end

    def validate_limits!
      raise ConfigError, 'SLEEP_INTERVAL must be greater than zero' unless @sleep_interval.positive?
      raise ConfigError, 'MAX_RETRIES must be greater than zero' unless @max_retries.positive?
    end
  end
end
