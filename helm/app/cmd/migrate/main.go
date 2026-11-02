package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/tessera-app/tessera/internal/migrate"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	if len(os.Args) != 2 || (os.Args[1] != "up" && os.Args[1] != "check") {
		return fmt.Errorf("usage: migrate up|check")
	}
	dsn := os.Getenv("TESSERA_DATABASE_DSN")
	if dsn == "" {
		return fmt.Errorf("TESSERA_DATABASE_DSN is required")
	}
	timeout := 5 * time.Minute
	if os.Args[1] == "check" {
		timeout = 20 * time.Second
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	conn, err := migrate.Connect(ctx, dsn)
	if err != nil {
		return err
	}
	defer conn.Close(context.Background())
	if os.Args[1] == "check" {
		return conn.Ping(ctx)
	}
	return migrate.Up(ctx, conn)
}
