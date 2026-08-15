# frozen_string_literal: true

require 'logger'
require 'pg'

require_relative '../lib/auto_planka'

# Helpers for the specs that talk to a real PostgreSQL database.
#
# Set TEST_DATABASE_URL to point at a scratch database; every example drops and
# recreates the public schema, so never aim this at a real Planka install.
module DatabaseHelper
  SCHEMA_FIXTURE = File.expand_path('fixtures/planka_v1_schema.sql', __dir__)

  module_function

  def database_url
    ENV.fetch('TEST_DATABASE_URL', 'postgres://postgres:postgres@localhost:5432/auto_planka_test')
  end

  def available?
    return @available unless @available.nil?

    @available = begin
      PG.connect(database_url).close
      true
    rescue PG::Error
      false
    end
  end

  def connect
    PG.connect(database_url)
  end

  def reset_schema(db)
    db.exec('SET client_min_messages TO WARNING')
    db.exec('DROP SCHEMA IF EXISTS public CASCADE')
    db.exec('CREATE SCHEMA public')
    db.exec(File.read(SCHEMA_FIXTURE))
  end
end

# Convenience row builders so examples read as data setup rather than SQL.
module FixtureHelper
  # Connection opened by the :database around hook.
  attr_reader :db

  def create_project(id, name: "Project #{id}")
    db.exec_params('INSERT INTO project (id, name, created_at) VALUES ($1, $2, now())', [id, name])
    id
  end

  def create_board(id, project_id:, position: 0, name: "Board #{id}")
    db.exec_params(
      'INSERT INTO board (id, project_id, position, name, created_at) VALUES ($1, $2, $3, $4, now())',
      [id, project_id, position, name]
    )
    id
  end

  def create_user(id, admin: false, deleted: false, email: "user#{id}@example.com")
    db.exec_params(
      'INSERT INTO user_account (id, email, is_admin, name, deleted_at) VALUES ($1, $2, $3, $4, $5)',
      [id, email, admin, "User #{id}", deleted ? Time.now : nil]
    )
    id
  end

  def create_label(id, board_id:, name:, color: 'berry-red', position: 0)
    db.exec_params(
      'INSERT INTO label (id, board_id, name, color, position, created_at) VALUES ($1, $2, $3, $4, $5, now())',
      [id, board_id, name, color, position]
    )
    id
  end

  def board_memberships
    db.exec('SELECT board_id, user_id, role FROM board_membership ORDER BY board_id, user_id').to_a
  end

  def project_managers
    db.exec('SELECT project_id, user_id FROM project_manager ORDER BY project_id, user_id').to_a
  end

  def labels
    db.exec('SELECT board_id, name, color FROM label ORDER BY board_id, name').to_a
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)

  # Keep test output clean; examples that care about logging inject their own.
  AutoPlanka.logger = Logger.new(File::NULL)

  config.include FixtureHelper, :database

  config.before(:suite) do
    warn "\nSkipping database specs: cannot connect to #{DatabaseHelper.database_url}" unless DatabaseHelper.available?
  end

  config.around(:each, :database) do |example|
    if DatabaseHelper.available?
      db = DatabaseHelper.connect
      DatabaseHelper.reset_schema(db)
      @db = db
      begin
        example.run
      ensure
        db.close
      end
    else
      skip 'no test database available'
    end
  end

  config.define_derived_metadata(file_path: %r{/spec/}) do |metadata|
    metadata[:aggregate_failures] = true
  end
end
