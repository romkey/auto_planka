# frozen_string_literal: true

module AutoPlanka
  # Base class for every error raised by this application.
  class Error < StandardError; end

  # Raised when the configuration file or environment is unusable.
  class ConfigError < Error; end

  # Raised when the database is not a Planka v1 database we can safely modify.
  class IncompatibleSchemaError < Error; end
end
