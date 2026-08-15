#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'

require_relative 'lib/auto_planka'

# Unbuffered so logs stream to `docker logs` instead of sitting in the pipe buffer
$stdout.sync = true

def run
  config = AutoPlanka::Config.from_env
  AutoPlanka::Runner.new(config).run
rescue AutoPlanka::ConfigError => e
  AutoPlanka.logger.fatal(e.message)
  1
end

exit(run) if File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)
