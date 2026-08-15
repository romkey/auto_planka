# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AutoPlanka::SchemaValidator, :database do
  subject(:validator) { described_class.new(db, logger: logger) }

  let(:logger) { instance_spy(Logger) }

  it 'accepts a Planka v1 schema' do
    expect { validator.validate! }.not_to raise_error
  end

  it 'rejects a database that is missing a Planka table' do
    db.exec('DROP TABLE board_membership')

    expect { validator.validate! }
      .to raise_error(AutoPlanka::IncompatibleSchemaError, /missing table\(s\): board_membership/)
  end

  it 'names every missing table' do
    db.exec('DROP TABLE board_membership')
    db.exec('DROP TABLE project_manager')

    expect { validator.validate! }
      .to raise_error(AutoPlanka::IncompatibleSchemaError, /board_membership, project_manager/)
  end

  it 'rejects an empty database' do
    db.exec('DROP SCHEMA public CASCADE')
    db.exec('CREATE SCHEMA public')

    expect { validator.validate! }.to raise_error(AutoPlanka::IncompatibleSchemaError)
  end

  context 'when the database has been upgraded to Planka v2' do
    before { db.exec('CREATE TABLE custom_field (id bigint PRIMARY KEY)') }

    it 'refuses to run' do
      expect { validator.validate! }
        .to raise_error(AutoPlanka::IncompatibleSchemaError, /Planka v2\+/)
    end

    it 'suggests the override in the error message' do
      expect { validator.validate! }
        .to raise_error(AutoPlanka::IncompatibleSchemaError, /SKIP_VERSION_CHECK=1/)
    end

    it 'continues with a warning when the check is skipped' do
      validator = described_class.new(db, logger: logger, skip_version_check: true)

      expect { validator.validate! }.not_to raise_error
      expect(logger).to have_received(:warn).with(/Planka v2\+/)
    end
  end
end
