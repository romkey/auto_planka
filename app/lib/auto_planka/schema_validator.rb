# frozen_string_literal: true

module AutoPlanka
  # Confirms the connected database is a Planka v1 database before we write to it.
  class SchemaValidator
    REQUIRED_TABLES = %w[
      board
      board_membership
      label
      project
      project_manager
      user_account
    ].freeze

    # Tables introduced by Planka v2. Their presence means the schema this
    # application was written against no longer applies.
    V2_TABLES = %w[
      base_custom_field_group
      custom_field
      custom_field_group
      custom_field_value
    ].freeze

    def initialize(db, logger: AutoPlanka.logger, skip_version_check: false)
      @db = db
      @logger = logger
      @skip_version_check = skip_version_check
    end

    # Raises IncompatibleSchemaError if the database cannot be used.
    def validate!
      @logger.info('Validating database schema...')
      tables = table_names

      check_required_tables(tables)
      check_planka_version(tables)
    end

    private

    def table_names
      @db.exec(
        'SELECT table_name FROM information_schema.tables ' \
        "WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
      ).map { |row| row['table_name'] }
    end

    def check_required_tables(tables)
      missing = REQUIRED_TABLES - tables
      unless missing.empty?
        raise IncompatibleSchemaError,
              "Not a Planka database - missing table(s): #{missing.join(', ')}"
      end

      @logger.info('All required tables present')
    end

    def check_planka_version(tables)
      found = V2_TABLES & tables

      if found.empty?
        @logger.info('Database schema is compatible with Planka v1.x')
        return
      end

      message = "Detected Planka v2+ schema (found table(s): #{found.join(', ')}). " \
                'This application only supports Planka v1.x.'

      raise IncompatibleSchemaError, "#{message} Set SKIP_VERSION_CHECK=1 to override." unless @skip_version_check

      @logger.warn("#{message} SKIP_VERSION_CHECK is set, continuing anyway.")
    end
  end
end
