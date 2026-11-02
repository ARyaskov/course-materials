package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config — полная конфигурация Tessera. Единственный источник значений — окружение.
// Все переменные имеют префикс TESSERA_ и читаются один раз при старте процесса.
type Config struct {
	Env             string        // dev | staging | prod
	HTTPAddr        string        // адрес основного HTTP-сервера
	AdminAddr       string        // адрес служебного сервера: /healthz, /readyz, /metrics
	LogLevel        string        // debug | info | warn | error
	DatabaseDSN     string        // postgres://user:pass@host:5432/tessera?sslmode=require
	DatabaseMaxConn int32         // верхняя граница пула соединений
	RedisAddr       string        // host:6379
	RedisPassword   string        // пустая строка = без пароля
	RedisDB         int           // номер базы Redis
	HoldTTL         time.Duration // время жизни брони места
	TicketSignKey   string        // ключ подписи QR-кода билета
	ShutdownGrace   time.Duration // сколько ждать завершения активных запросов
}

// Load читает конфигурацию из окружения и падает с понятной ошибкой,
// если обязательное значение отсутствует или не разбирается.
func Load() (*Config, error) {
	var problems []string
	req := func(key string) string {
		v := strings.TrimSpace(os.Getenv("TESSERA_" + key))
		if v == "" {
			problems = append(problems, "TESSERA_"+key+" is required")
		}
		return v
	}
	opt := func(key, def string) string {
		if v := strings.TrimSpace(os.Getenv("TESSERA_" + key)); v != "" {
			return v
		}
		return def
	}
	dur := func(key, def string) time.Duration {
		raw := opt(key, def)
		d, err := time.ParseDuration(raw)
		if err != nil {
			problems = append(problems, "TESSERA_"+key+": "+raw+" is not a duration")
		}
		return d
	}
	num := func(key, def string) int {
		raw := opt(key, def)
		n, err := strconv.Atoi(raw)
		if err != nil {
			problems = append(problems, "TESSERA_"+key+": "+raw+" is not a number")
		}
		return n
	}

	cfg := &Config{
		Env:             opt("ENV", "dev"),
		HTTPAddr:        opt("HTTP_ADDR", ":8080"),
		AdminAddr:       opt("ADMIN_ADDR", ":9090"),
		LogLevel:        opt("LOG_LEVEL", "info"),
		DatabaseDSN:     req("DATABASE_DSN"),
		DatabaseMaxConn: int32(num("DATABASE_MAX_CONN", "10")),
		RedisAddr:       req("REDIS_ADDR"),
		RedisPassword:   opt("REDIS_PASSWORD", ""),
		RedisDB:         num("REDIS_DB", "0"),
		HoldTTL:         dur("HOLD_TTL", "10m"),
		TicketSignKey:   req("TICKET_SIGN_KEY"),
		ShutdownGrace:   dur("SHUTDOWN_GRACE", "20s"),
	}
	if len(problems) > 0 {
		return nil, fmt.Errorf("invalid configuration:\n  %s", strings.Join(problems, "\n  "))
	}
	return cfg, nil
}
