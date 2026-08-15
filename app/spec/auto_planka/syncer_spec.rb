# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AutoPlanka::Syncer, :database do
  subject(:syncer) { described_class.new(db, public_project_ids: public_project_ids, logger: logger) }

  let(:logger) { instance_spy(Logger) }
  let(:public_project_ids) { ['1001'] }

  # One public project with two boards, plus a private project that must be
  # left alone. Users: one admin, one regular, one soft-deleted.
  before do
    create_project(1001, name: 'Public')
    create_project(1002, name: 'Private')
    create_board(2001, project_id: 1001)
    create_board(2002, project_id: 1001, position: 1)
    create_board(2003, project_id: 1002)

    create_user(3001, admin: true)
    create_user(3002)
    create_user(3003, deleted: true)
  end

  describe 'board memberships' do
    it 'adds every active user to every board of a public project' do
      syncer.run_once

      expect(board_memberships).to contain_exactly(
        { 'board_id' => '2001', 'user_id' => '3001', 'role' => 'editor' },
        { 'board_id' => '2001', 'user_id' => '3002', 'role' => 'editor' },
        { 'board_id' => '2002', 'user_id' => '3001', 'role' => 'editor' },
        { 'board_id' => '2002', 'user_id' => '3002', 'role' => 'editor' }
      )
    end

    it 'leaves boards outside the public projects untouched' do
      syncer.run_once

      expect(board_memberships.map { |row| row['board_id'] }).not_to include('2003')
    end

    it 'excludes soft-deleted users' do
      syncer.run_once

      expect(board_memberships.map { |row| row['user_id'] }).not_to include('3003')
    end

    it 'honours the configured role' do
      described_class.new(db, public_project_ids: public_project_ids, role: 'viewer', logger: logger).run_once

      expect(board_memberships.map { |row| row['role'] }.uniq).to eq(['viewer'])
    end

    it 'picks up users created after the first pass' do
      syncer.run_once
      expect(board_memberships.length).to eq(4)

      create_user(3004)
      syncer.run_once

      expect(board_memberships.length).to eq(6)
    end

    it 'does not downgrade a member who was promoted by hand' do
      db.exec("UPDATE board_membership SET role = 'viewer' WHERE false")
      syncer.run_once
      db.exec("UPDATE board_membership SET role = 'viewer' WHERE board_id = 2001 AND user_id = 3002")

      syncer.run_once

      role = db.exec('SELECT role FROM board_membership WHERE board_id = 2001 AND user_id = 3002').first['role']
      expect(role).to eq('viewer')
    end
  end

  describe 'project managers' do
    it 'makes admins managers of each public project' do
      syncer.run_once

      expect(project_managers).to eq([{ 'project_id' => '1001', 'user_id' => '3001' }])
    end

    it 'does not make regular users managers' do
      syncer.run_once

      expect(project_managers.map { |row| row['user_id'] }).not_to include('3002')
    end
  end

  describe 'labels' do
    it 'propagates a label to every other public board' do
      create_label(4001, board_id: 2001, name: 'Urgent')

      syncer.run_once

      expect(labels).to contain_exactly(
        { 'board_id' => '2001', 'name' => 'Urgent', 'color' => 'berry-red' },
        { 'board_id' => '2002', 'name' => 'Urgent', 'color' => 'berry-red' }
      )
    end

    it 'does not copy labels onto private boards' do
      create_label(4001, board_id: 2001, name: 'Urgent')

      syncer.run_once

      expect(labels.map { |row| row['board_id'] }).not_to include('2003')
    end

    it 'quotes label names containing SQL syntax' do
      evil = "'); DROP TABLE board_membership; --"
      create_label(4001, board_id: 2001, name: evil)

      syncer.run_once

      expect(labels.map { |row| row['name'] }).to eq([evil, evil])
      expect(db.exec("SELECT to_regclass('board_membership') AS t").first['t']).to eq('board_membership')
    end

    it 'ignores labels with no name' do
      db.exec_params(
        'INSERT INTO label (id, board_id, name, color, position, created_at) VALUES ($1, $2, NULL, $3, $4, now())',
        [4001, 2001, 'berry-red', 0]
      )

      syncer.run_once

      expect(labels.length).to eq(1)
    end
  end

  describe 'repeated passes' do
    it 'reports what it inserted on the first pass' do
      create_label(4001, board_id: 2001, name: 'Urgent')

      expect(syncer.run_once).to eq(memberships: 4, managers: 1, labels: 1)
    end

    it 'inserts nothing once the database has converged' do
      create_label(4001, board_id: 2001, name: 'Urgent')
      syncer.run_once

      expect(syncer.run_once).to eq(memberships: 0, managers: 0, labels: 0)
    end

    it 'does not accumulate duplicate rows' do
      create_label(4001, board_id: 2001, name: 'Urgent')
      3.times { syncer.run_once }

      expect(board_memberships.length).to eq(4)
      expect(project_managers.length).to eq(1)
      expect(labels.length).to eq(2)
    end
  end

  describe 'when no boards match' do
    let(:public_project_ids) { ['9999'] }

    it 'does nothing and warns' do
      expect(syncer.run_once).to eq(memberships: 0, managers: 0, labels: 0)

      expect(board_memberships).to be_empty
      expect(logger).to have_received(:warn).with(/No boards found/)
    end
  end

  describe 'failure handling' do
    it 'rolls the whole pass back if one statement fails' do
      db.exec('DROP TABLE label')

      expect { syncer.run_once }.to raise_error(PG::Error)
      expect(board_memberships).to be_empty
      expect(project_managers).to be_empty
    end
  end
end
