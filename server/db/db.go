// Package db provides a PostgreSQL connection pool and schema migration for
// the PowerSync backend. It uses pgx/v5 to connect to a local (or remote)
// Postgres instance.
package db

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Pool wraps a pgxpool connection pool.
type Pool struct {
	*pgxpool.Pool
	log *slog.Logger
}

// Connect opens a connection pool to the Postgres instance at uri and runs
// schema migrations. It will retry a few times to tolerate slow starts.
func Connect(ctx context.Context, uri string, log *slog.Logger) (*Pool, error) {
	cfg, err := pgxpool.ParseConfig(uri)
	if err != nil {
		return nil, fmt.Errorf("db: parse config: %w", err)
	}

	cfg.MaxConns = 10
	cfg.MinConns = 1
	cfg.MaxConnLifetime = 30 * time.Minute
	cfg.MaxConnIdleTime = 5 * time.Minute
	cfg.HealthCheckPeriod = 1 * time.Minute

	var pool *pgxpool.Pool
	for i := range 5 {
		pool, err = pgxpool.NewWithConfig(ctx, cfg)
		if err == nil {
			if pingErr := pool.Ping(ctx); pingErr == nil {
				break
			} else {
				err = pingErr
				pool.Close()
			}
		}
		wait := time.Duration(i+1) * 500 * time.Millisecond
		log.Warn("postgres not ready, retrying", "attempt", i+1, "wait", wait, "err", err)
		time.Sleep(wait)
	}
	if err != nil {
		return nil, fmt.Errorf("db: connect to postgres: %w", err)
	}

	p := &Pool{Pool: pool, log: log}
	if err := p.migrate(ctx); err != nil {
		pool.Close()
		return nil, err
	}

	log.Info("postgres connected", "dsn", redactDSN(uri))
	return p, nil
}

// migrate creates the initial schema. Add new statements here as your app grows.
// This is intentionally simple – use a proper migration tool (golang-migrate, goose)
// when you need versioned migrations.
func (p *Pool) migrate(ctx context.Context) error {
	stmts := []string{
		// Example todos table – replace / extend with your own schema.
		`CREATE TABLE IF NOT EXISTS todos (
			id          TEXT        PRIMARY KEY,
			list_id     TEXT        NOT NULL,
			created_by  TEXT        NOT NULL,
			description TEXT        NOT NULL DEFAULT '',
			completed   BOOLEAN     NOT NULL DEFAULT FALSE,
			created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
			updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
		)`,
		`CREATE TABLE IF NOT EXISTS lists (
			id          TEXT        PRIMARY KEY,
			created_by  TEXT        NOT NULL,
			name        TEXT        NOT NULL DEFAULT '',
			created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
			updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
		)`,
	}

	for _, s := range stmts {
		if _, err := p.Exec(ctx, s); err != nil {
			return fmt.Errorf("db: migration failed: %w", err)
		}
	}
	p.log.Info("db: schema up-to-date")
	return nil
}

// redactDSN hides the password from the connection string for safe logging.
func redactDSN(uri string) string {
	cfg, err := pgxpool.ParseConfig(uri)
	if err != nil {
		return "<invalid dsn>"
	}
	cfg.ConnConfig.Password = "***"
	return cfg.ConnConfig.ConnString()
}
