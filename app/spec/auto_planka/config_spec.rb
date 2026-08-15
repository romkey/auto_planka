# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

require 'spec_helper'

RSpec.describe AutoPlanka::Config do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmpdir) }

  def write_config(contents)
    path = File.join(tmpdir, 'config.json')
    File.write(path, contents)
    path
  end

  describe '.from_env' do
    let(:env) do
      {
        'CONFIG_PATH' => write_config('{"public_project_ids": ["1001", "1002"]}'),
        'POSTGRESQL' => 'postgres://localhost/planka'
      }
    end

    it 'reads the project IDs and database URL' do
      config = described_class.from_env(env)

      expect(config.public_project_ids).to eq(%w[1001 1002])
      expect(config.database_url).to eq('postgres://localhost/planka')
    end

    it 'applies defaults for the optional settings' do
      config = described_class.from_env(env)

      expect(config.role).to eq('editor')
      expect(config.sleep_interval).to eq(60)
      expect(config.max_retries).to eq(5)
      expect(config.skip_version_check?).to be(false)
    end

    it 'reads the optional settings from the environment' do
      config = described_class.from_env(
        env.merge(
          'DEFAULT_ROLE' => 'viewer',
          'SLEEP_INTERVAL' => '15',
          'MAX_RETRIES' => '2',
          'SKIP_VERSION_CHECK' => '1'
        )
      )

      expect(config.role).to eq('viewer')
      expect(config.sleep_interval).to eq(15)
      expect(config.max_retries).to eq(2)
      expect(config.skip_version_check?).to be(true)
    end

    it 'coerces numeric project IDs to strings' do
      env['CONFIG_PATH'] = write_config('{"public_project_ids": [1001]}')

      expect(described_class.from_env(env).public_project_ids).to eq(['1001'])
    end

    it 'raises when the config file is missing' do
      env['CONFIG_PATH'] = File.join(tmpdir, 'nope.json')

      expect { described_class.from_env(env) }
        .to raise_error(AutoPlanka::ConfigError, /Config file not found/)
    end

    it 'raises when the config file is not valid JSON' do
      env['CONFIG_PATH'] = write_config('{ this is not json')

      expect { described_class.from_env(env) }
        .to raise_error(AutoPlanka::ConfigError, /Invalid JSON/)
    end

    it 'raises when public_project_ids is missing or empty' do
      env['CONFIG_PATH'] = write_config('{"public_project_ids": []}')

      expect { described_class.from_env(env) }
        .to raise_error(AutoPlanka::ConfigError, /public_project_ids/)
    end

    it 'rejects project IDs that are not numeric Planka IDs' do
      env['CONFIG_PATH'] = write_config(%({"public_project_ids": ["1001'; DROP TABLE board; --"]}))

      expect { described_class.from_env(env) }
        .to raise_error(AutoPlanka::ConfigError, /must be numeric Planka IDs/)
    end

    it 'raises when POSTGRESQL is not set' do
      env.delete('POSTGRESQL')

      expect { described_class.from_env(env) }
        .to raise_error(AutoPlanka::ConfigError, /POSTGRESQL/)
    end

    it 'raises on an unknown role' do
      expect { described_class.from_env(env.merge('DEFAULT_ROLE' => 'owner')) }
        .to raise_error(AutoPlanka::ConfigError, /DEFAULT_ROLE/)
    end

    it 'raises on a non-positive sleep interval' do
      expect { described_class.from_env(env.merge('SLEEP_INTERVAL' => '0')) }
        .to raise_error(AutoPlanka::ConfigError, /SLEEP_INTERVAL/)
    end
  end
end
