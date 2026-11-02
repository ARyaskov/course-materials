package httpapi

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/tessera-app/tessera/internal/cache"
	"github.com/tessera-app/tessera/internal/config"
	"github.com/tessera-app/tessera/internal/health"
	"github.com/tessera-app/tessera/internal/store"
)

// Router — публичный HTTP API на порту 8080. Сюда приходит трафик из Ingress.
func Router(db *store.DB, rdb *cache.Cache, cfg *config.Config) http.Handler {
	mux := http.NewServeMux()
	h := &handlers{db: db, cache: rdb, cfg: cfg}
	mux.HandleFunc("GET /api/v1/events", h.listEvents)
	mux.HandleFunc("GET /api/v1/events/{id}/seats", h.listSeats)
	mux.HandleFunc("POST /api/v1/orders", h.createOrder)
	mux.HandleFunc("POST /api/v1/orders/{id}/pay", h.payOrder)
	mux.HandleFunc("POST /api/v1/checkins", h.checkIn)
	return withRequestLog(mux)
}

// AdminRouter — служебный порт 9090: пробы и метрики.
// Он намеренно отделён от публичного, чтобы probes и /metrics
// не попадали наружу через Ingress и не делили лимиты с боевым трафиком.
func AdminRouter(probes *health.Registry) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", probes.Live)
	mux.HandleFunc("GET /readyz", probes.Ready)
	mux.Handle("GET /metrics", promhttp.Handler())
	return mux
}
