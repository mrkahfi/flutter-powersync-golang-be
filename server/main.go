package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"

	"github.com/joho/godotenv"

	"powersync-backend/auth"
	"powersync-backend/config"
	"powersync-backend/db"
	"powersync-backend/handler"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))

	// Load .env file if present (ignored in production where env vars are set directly).
	if err := godotenv.Load(); err != nil {
		log.Info("no .env file found, using environment variables")
	}

	cfg, err := config.Load()
	if err != nil {
		log.Error("load config", "err", err)
		os.Exit(1)
	}

	authMgr, err := auth.New(cfg)
	if err != nil {
		log.Error("create auth manager", "err", err)
		os.Exit(1)
	}

	if cfg.DevMode {
		log.Warn("running in DEV MODE — do not use in production!")
	}

	// Connect to Postgres.
	ctx := context.Background()
	pool, err := db.Connect(ctx, cfg.DatabaseURI, log)
	if err != nil {
		log.Error("connect to database", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	mux := http.NewServeMux()
	handler.New(mux, authMgr, pool, log)

	addr := fmt.Sprintf(":%s", cfg.Port)
	log.Info("PowerSync backend listening", "addr", addr)

	if err := http.ListenAndServe(addr, corsMiddleware(mux)); err != nil {
		log.Error("server error", "err", err)
		os.Exit(1)
	}
}

// corsMiddleware adds permissive CORS headers for local Flutter development.
// Tighten this for production by restricting allowed origins.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
