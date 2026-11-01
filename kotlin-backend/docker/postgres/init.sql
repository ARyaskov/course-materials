-- Только то, что Flyway не делает: расширения и роли (урок 15.3)
CREATE EXTENSION IF NOT EXISTS btree_gist;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'atrium_readonly') THEN
    CREATE ROLE atrium_readonly LOGIN PASSWORD 'readonly';
  END IF;
END $$;
GRANT CONNECT ON DATABASE atrium TO atrium_readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE atrium IN SCHEMA public GRANT SELECT ON TABLES TO atrium_readonly;
