package migrate

import (
	"context"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/tessera-app/tessera/migrations"
)

// Connect waits for PostgreSQL within the caller's deadline. Credentials are
// deliberately omitted from returned errors and logs.
func Connect(ctx context.Context, dsn string) (*pgx.Conn, error) {
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("invalid database DSN")
	}
	cfg.ConnectTimeout = 2 * time.Second
	for {
		conn, err := pgx.ConnectConfig(ctx, cfg)
		if err == nil {
			return conn, nil
		}
		select {
		case <-ctx.Done():
			return nil, fmt.Errorf("database not ready: %w", ctx.Err())
		case <-time.After(time.Second):
		}
	}
}

// Up serializes concurrent releases and commits each migration and its version
// in one PostgreSQL transaction. Failed DDL is rolled back with its version.
func Up(ctx context.Context, conn *pgx.Conn) error {
	if _, err := conn.Exec(ctx, "SELECT pg_advisory_lock(734015923)"); err != nil {
		return err
	}
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_, _ = conn.Exec(cleanup, "SELECT pg_advisory_unlock(734015923)")
	}()
	if _, err := conn.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version bigint PRIMARY KEY, dirty boolean NOT NULL DEFAULT false)`); err != nil {
		return err
	}
	names, err := fs.Glob(migrations.Files, "*.up.sql")
	if err != nil {
		return err
	}
	sort.Strings(names)
	for _, name := range names {
		version, err := strconv.ParseInt(strings.SplitN(name, "_", 2)[0], 10, 64)
		if err != nil {
			return fmt.Errorf("invalid migration name %s", name)
		}
		var done bool
		if err := conn.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version=$1)", version).Scan(&done); err != nil {
			return err
		}
		if done {
			continue
		}
		body, err := migrations.Files.ReadFile(name)
		if err != nil {
			return err
		}
		if err := apply(ctx, conn, version, string(body)); err != nil {
			return fmt.Errorf("migration %s failed: %w", name, err)
		}
	}
	return nil
}

func apply(ctx context.Context, conn *pgx.Conn, version int64, sql string) error {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background())
	if _, err := tx.Exec(ctx, sql); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "INSERT INTO schema_migrations(version) VALUES($1)", version); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
