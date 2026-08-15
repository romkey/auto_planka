# frozen_string_literal: true

module AutoPlanka
  # Performs one synchronisation pass over the configured public projects.
  #
  # Every statement is an idempotent bulk INSERT ... ON CONFLICT DO NOTHING, so
  # repeated passes are cheap once the database has converged.
  class Syncer
    TIMESTAMP_FORMAT = '%Y-%m-%d %H:%M:%S.%L'

    def initialize(db, public_project_ids:, role: Config::DEFAULT_ROLE, logger: AutoPlanka.logger)
      @db = db
      @public_project_ids = public_project_ids
      @role = role
      @logger = logger
    end

    # Returns a hash of how many rows each step inserted.
    def run_once(now: Time.now)
      timestamp = now.strftime(TIMESTAMP_FORMAT)
      board_ids = public_board_ids

      if board_ids.empty?
        @logger.warn('No boards found for the configured public project IDs')
        return { memberships: 0, managers: 0, labels: 0 }
      end

      counts = {}
      @db.transaction do
        counts[:memberships] = add_all_users_to_boards(timestamp, board_ids)
        counts[:managers] = add_admins_as_project_managers(timestamp)
        counts[:labels] = propagate_labels(timestamp, board_ids)
      end

      report(counts)
      counts
    end

    private

    def quote(value)
      @db.escape_literal(value.to_s)
    end

    def quote_list(values)
      values.map { |value| quote(value) }.join(',')
    end

    def public_board_ids
      @db.exec("SELECT id FROM board WHERE project_id IN (#{quote_list(@public_project_ids)})")
         .map { |row| row['id'] }
    end

    def insert(sql)
      @db.exec(sql).cmd_tuples
    end

    # Every user becomes a member of every board in a public project.
    def add_all_users_to_boards(timestamp, board_ids)
      user_ids = @db.exec('SELECT id FROM user_account WHERE deleted_at IS NULL').map { |row| row['id'] }
      return 0 if user_ids.empty?

      rows = board_ids.flat_map do |board_id|
        user_ids.map do |user_id|
          "(next_id(), #{quote(board_id)}, #{quote(user_id)}, #{quote(timestamp)}, NULL, #{quote(@role)}, NULL)"
        end
      end

      insert(
        'INSERT INTO board_membership (id, board_id, user_id, created_at, updated_at, role, can_comment) ' \
        "VALUES #{rows.join(',')} ON CONFLICT DO NOTHING"
      )
    end

    # Every Planka admin becomes a manager of every public project.
    def add_admins_as_project_managers(timestamp)
      admin_ids = @db.exec("SELECT id FROM user_account WHERE is_admin = 't' AND deleted_at IS NULL")
                     .map { |row| row['id'] }
      return 0 if admin_ids.empty?

      rows = @public_project_ids.flat_map do |project_id|
        admin_ids.map do |admin_id|
          "(next_id(), #{quote(project_id)}, #{quote(admin_id)}, #{quote(timestamp)}, NULL)"
        end
      end

      insert(
        'INSERT INTO project_manager (id, project_id, user_id, created_at, updated_at) ' \
        "VALUES #{rows.join(',')} ON CONFLICT DO NOTHING"
      )
    end

    # Any label defined on one public board is made available on all of them.
    # Requires a unique index on label (name, board_id); see the README.
    def propagate_labels(timestamp, board_ids)
      labels = @db.exec(
        'SELECT DISTINCT ON (name) name, color, position FROM label ' \
        "WHERE board_id IN (#{quote_list(board_ids)}) AND name IS NOT NULL ORDER BY name, created_at"
      ).to_a
      return 0 if labels.empty?

      rows = labels.flat_map do |label|
        board_ids.map do |board_id|
          "(next_id(), #{quote(board_id)}, #{quote(label['name'])}, #{quote(label['color'])}, " \
            "#{quote(timestamp)}, NULL, #{quote(label['position'])})"
        end
      end

      insert(
        'INSERT INTO label (id, board_id, name, color, created_at, updated_at, position) ' \
        "VALUES #{rows.join(',')} ON CONFLICT DO NOTHING"
      )
    end

    # Steady state inserts nothing, so only speak up when something changed.
    def report(counts)
      if counts.values.sum.zero?
        @logger.debug('Nothing to do, everything already in sync')
        return
      end

      @logger.info(
        format(
          'Added %<memberships>d board membership(s), %<managers>d project manager(s), %<labels>d label(s)',
          counts
        )
      )
    end
  end
end
