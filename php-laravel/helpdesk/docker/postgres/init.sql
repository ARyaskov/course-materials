-- docker/postgres/init.sql
CREATE DATABASE helpdesk_test OWNER helpdesk;

\c helpdesk

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
