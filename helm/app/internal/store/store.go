package store

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DB — тонкая обёртка над пулом соединений PostgreSQL.
// Размер пула ограничен сверху: max_connections сервера делится
// между всеми репликами API и worker, поэтому число реплик и MaxConns связаны.
type DB struct{ pool *pgxpool.Pool }

func Open(ctx context.Context, dsn string, maxConn int32) (*DB, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("invalid database DSN")
	}
	cfg.MaxConns = maxConn
	cfg.MaxConnLifetime = 30 * time.Minute
	cfg.MaxConnIdleTime = 5 * time.Minute

	// Соединение устанавливается лениво: приложение обязано подниматься,
	// даже если база в этот момент недоступна. Недоступность отражается
	// в /readyz, а не в падении процесса.
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	return &DB{pool: pool}, nil
}

func (d *DB) Ping(ctx context.Context) error { return d.pool.Ping(ctx) }
func (d *DB) Close()                         { d.pool.Close() }
func (d *DB) Pool() *pgxpool.Pool            { return d.pool }
