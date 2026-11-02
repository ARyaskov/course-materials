package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tessera-app/tessera/internal/cache"
	"github.com/tessera-app/tessera/internal/config"
	"github.com/tessera-app/tessera/internal/health"
	"github.com/tessera-app/tessera/internal/httpapi"
	"github.com/tessera-app/tessera/internal/store"
)

func main() {
	if err := run(); err != nil {
		slog.Error("startup failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: parseLevel(cfg.LogLevel)}))
	slog.SetDefault(logger)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	db, err := store.Open(ctx, cfg.DatabaseDSN, cfg.DatabaseMaxConn)
	if err != nil {
		return err
	}
	defer db.Close()

	rdb, err := cache.Open(ctx, cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB)
	if err != nil {
		return err
	}
	defer rdb.Close()

	probes := health.New(2*time.Second,
		health.Checker{Name: "postgres", Probe: db.Ping},
		health.Checker{Name: "redis", Probe: rdb.Ping},
	)

	api := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           httpapi.Router(db, rdb, cfg),
		ReadHeaderTimeout: 5 * time.Second,
	}
	admin := &http.Server{
		Addr:              cfg.AdminAddr,
		Handler:           httpapi.AdminRouter(probes),
		ReadHeaderTimeout: 5 * time.Second,
	}

	errCh := make(chan error, 2)
	go serve(api, "api", errCh)
	go serve(admin, "admin", errCh)
	slog.Info("tessera api started", "env", cfg.Env, "http", cfg.HTTPAddr, "admin", cfg.AdminAddr)

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}

	// Шаг 1: сказать кластеру «сюда больше не надо» до того, как что-то ломается.
	// Endpoints обновляются не мгновенно, поэтому какое-то время сюда ещё придут запросы,
	// и обслужить их обязаны.
	slog.Info("SIGTERM received, draining")
	probes.BeginShutdown()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownGrace)
	defer cancel()

	// Шаг 2: перестать принимать новые соединения и дождаться активных запросов.
	if err := api.Shutdown(shutdownCtx); err != nil {
		slog.Error("api shutdown", "error", err)
	}
	if err := admin.Shutdown(shutdownCtx); err != nil {
		slog.Error("admin shutdown", "error", err)
	}
	slog.Info("tessera api stopped")
	return nil
}

func serve(s *http.Server, name string, errCh chan<- error) {
	if err := s.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		errCh <- err
	}
}

func parseLevel(s string) slog.Level {
	switch s {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
