package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
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
	check := flag.Bool("healthcheck", false, "check the running worker's admin endpoint")
	flag.Parse()
	var err error
	if *check {
		addr := os.Getenv("TESSERA_ADMIN_ADDR")
		if addr == "" {
			addr = ":9090"
		}
		_, port, addressErr := net.SplitHostPort(addr)
		if addressErr != nil {
			slog.Error("invalid TESSERA_ADMIN_ADDR")
			os.Exit(1)
		}
		client := &http.Client{Timeout: 2 * time.Second}
		var response *http.Response
		response, err = client.Get("http://" + net.JoinHostPort("127.0.0.1", port) + "/healthz")
		if err == nil {
			response.Body.Close()
			if response.StatusCode != http.StatusOK {
				err = fmt.Errorf("worker is unhealthy")
			}
		}
	} else {
		err = run()
	}
	if err != nil {
		slog.Error("worker failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
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
	probes := health.New(2*time.Second, health.Checker{Name: "postgres", Probe: db.Ping}, health.Checker{Name: "redis", Probe: rdb.Ping})
	server := &http.Server{Addr: cfg.AdminAddr, Handler: httpapi.AdminRouter(probes), ReadHeaderTimeout: 5 * time.Second}
	errCh := make(chan error, 1)
	go func() {
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			probes.BeginShutdown()
			shutdown, cancel := context.WithTimeout(context.Background(), cfg.ShutdownGrace)
			defer cancel()
			return server.Shutdown(shutdown)
		case err := <-errCh:
			return err
		case <-ticker.C:
			jobCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
			n, err := db.ExpireOrders(jobCtx)
			cancel()
			if err != nil {
				slog.Error("expire orders failed", "error", err)
			} else if n > 0 {
				slog.Info("orders expired", "count", n)
			}
		}
	}
}
