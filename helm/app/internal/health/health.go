package health

import (
	"context"
	"encoding/json"
	"net/http"
	"sync/atomic"
	"time"
)

// Checker — одна именованная проверка зависимости для /readyz.
type Checker struct {
	Name  string
	Probe func(context.Context) error
}

// Registry собирает проверки готовности и хранит флаг «сервис выключается».
// Liveness намеренно не смотрит на зависимости: недоступная база — не повод
// перезапускать процесс, иначе кратковременный сбой БД превращается
// в перезапуск всех реплик сразу.
type Registry struct {
	checks       []Checker
	shuttingDown atomic.Bool
	timeout      time.Duration
}

func New(timeout time.Duration, checks ...Checker) *Registry {
	return &Registry{checks: checks, timeout: timeout}
}

// BeginShutdown переводит /readyz в 503. Вызывается сразу по SIGTERM,
// до того как процесс начнёт закрывать соединения.
func (r *Registry) BeginShutdown() { r.shuttingDown.Store(true) }

// Live отвечает на livenessProbe: процесс запущен и обслуживает HTTP.
func (r *Registry) Live(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

// Ready отвечает на readinessProbe: можно ли направлять сюда трафик.
func (r *Registry) Ready(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.shuttingDown.Load() {
		w.WriteHeader(http.StatusServiceUnavailable)
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "shutting-down"})
		return
	}
	ctx, cancel := context.WithTimeout(req.Context(), r.timeout)
	defer cancel()

	result := make(map[string]string, len(r.checks))
	ok := true
	for _, c := range r.checks {
		if err := c.Probe(ctx); err != nil {
			result[c.Name] = "fail"
			ok = false
			continue
		}
		result[c.Name] = "ok"
	}
	if !ok {
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	_ = json.NewEncoder(w).Encode(result)
}
