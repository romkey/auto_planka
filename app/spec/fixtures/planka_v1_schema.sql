-- Minimal reproduction of the Planka v1 tables that auto_planka reads and writes.
-- Column order and the unique indexes match Planka so the ON CONFLICT clauses
-- behave the same way they do in production.

CREATE SEQUENCE next_id_seq;

CREATE FUNCTION next_id() RETURNS bigint AS $$
  SELECT nextval('next_id_seq')::bigint;
$$ LANGUAGE sql;

CREATE TABLE project (
  id bigint NOT NULL DEFAULT next_id() PRIMARY KEY,
  name text NOT NULL,
  created_at timestamp,
  updated_at timestamp
);

CREATE TABLE board (
  id bigint NOT NULL DEFAULT next_id() PRIMARY KEY,
  project_id bigint NOT NULL,
  position double precision NOT NULL,
  name text NOT NULL,
  created_at timestamp,
  updated_at timestamp
);

CREATE TABLE user_account (
  id bigint NOT NULL DEFAULT next_id() PRIMARY KEY,
  email text NOT NULL,
  password text,
  is_admin boolean NOT NULL DEFAULT false,
  name text NOT NULL,
  username text,
  phone text,
  organization text,
  subscribe_to_own_cards boolean NOT NULL DEFAULT false,
  created_at timestamp,
  updated_at timestamp,
  deleted_at timestamp,
  language text,
  password_changed_at timestamp,
  avatar jsonb,
  is_sso boolean NOT NULL DEFAULT false
);

CREATE TABLE board_membership (
  id bigint NOT NULL DEFAULT next_id() PRIMARY KEY,
  board_id bigint NOT NULL,
  user_id bigint NOT NULL,
  created_at timestamp,
  updated_at timestamp,
  role text NOT NULL,
  can_comment boolean
);
CREATE UNIQUE INDEX board_membership_board_id_user_id_idx ON board_membership (board_id, user_id);

CREATE TABLE label (
  id bigint NOT NULL DEFAULT next_id() PRIMARY KEY,
  board_id bigint NOT NULL,
  name text,
  color text NOT NULL,
  created_at timestamp,
  updated_at timestamp,
  position double precision NOT NULL
);
-- Added manually by the operator; see the README.
ALTER TABLE label ADD UNIQUE (name, board_id);

CREATE TABLE project_manager (
  id bigint NOT NULL DEFAULT next_id() PRIMARY KEY,
  project_id bigint NOT NULL,
  user_id bigint NOT NULL,
  created_at timestamp,
  updated_at timestamp
);
CREATE UNIQUE INDEX project_manager_project_id_user_id_idx ON project_manager (project_id, user_id);

CREATE TABLE migration (
  id serial PRIMARY KEY,
  name text NOT NULL
);
