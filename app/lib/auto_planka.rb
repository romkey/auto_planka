# frozen_string_literal: true

require 'logger'

require_relative 'auto_planka/errors'
require_relative 'auto_planka/config'
require_relative 'auto_planka/schema_validator'
require_relative 'auto_planka/syncer'
require_relative 'auto_planka/runner'

# Keeps Planka "public" projects in sync by granting every user access to the
# boards of the projects listed in the configuration file.
module AutoPlanka
  class << self
    attr_writer :logger

    def logger
      @logger ||= build_logger
    end

    private

    def build_logger
      logger = Logger.new($stdout)
      logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'INFO').upcase)
      logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
      logger
    end
  end
end
