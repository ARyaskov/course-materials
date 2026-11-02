package httpapi

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/tessera-app/tessera/internal/cache"
	"github.com/tessera-app/tessera/internal/config"
	"github.com/tessera-app/tessera/internal/store"
)

type handlers struct {
	db    *store.DB
	cache *cache.Cache
	cfg   *config.Config
}

var uuidPattern = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

func reply(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func problem(w http.ResponseWriter, status int) {
	reply(w, status, map[string]string{"error": http.StatusText(status)})
}

func decode(w http.ResponseWriter, r *http.Request, value any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(value); err != nil {
		problem(w, 400)
		return false
	}
	if err := d.Decode(new(any)); !errors.Is(err, io.EOF) {
		problem(w, 400)
		return false
	}
	return true
}

func respondError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		problem(w, 404)
	case errors.Is(err, store.ErrConflict):
		problem(w, 409)
	default:
		problem(w, 503)
	}
}

func (h *handlers) listEvents(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.Events(r.Context())
	if err != nil {
		respondError(w, err)
		return
	}
	reply(w, 200, rows)
}

func (h *handlers) listSeats(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !uuidPattern.MatchString(id) {
		problem(w, 400)
		return
	}
	rows, err := h.db.Seats(r.Context(), id)
	if err != nil {
		respondError(w, err)
		return
	}
	reply(w, 200, rows)
}

func (h *handlers) createOrder(w http.ResponseWriter, r *http.Request) {
	var request struct {
		EventID string   `json:"event_id"`
		SeatIDs []string `json:"seat_ids"`
	}
	if !decode(w, r, &request) {
		return
	}
	if !uuidPattern.MatchString(request.EventID) || len(request.SeatIDs) == 0 || len(request.SeatIDs) > 20 {
		problem(w, 400)
		return
	}
	seen := map[string]bool{}
	for i, id := range request.SeatIDs {
		id = strings.ToLower(id)
		if !uuidPattern.MatchString(id) || seen[id] {
			problem(w, 400)
			return
		}
		seen[id] = true
		request.SeatIDs[i] = id
	}
	if err := h.cache.Ping(r.Context()); err != nil {
		problem(w, 503)
		return
	}
	o, err := h.db.CreateOrder(r.Context(), request.EventID, request.SeatIDs, h.cfg.HoldTTL)
	if err != nil {
		respondError(w, err)
		return
	}
	// Redis is an expendable copy; PostgreSQL locks enforce reservation uniqueness.
	for _, seat := range request.SeatIDs {
		_, _ = h.cache.Hold(r.Context(), seat, o.ID, h.cfg.HoldTTL)
	}
	reply(w, http.StatusCreated, o)
}

func (h *handlers) payOrder(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !uuidPattern.MatchString(id) {
		problem(w, 400)
		return
	}
	tickets, err := h.db.PayOrder(r.Context(), id, h.sign)
	if err != nil {
		respondError(w, err)
		return
	}
	reply(w, 200, map[string]any{"tickets": tickets})
}

func (h *handlers) checkIn(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Code string `json:"code"`
	}
	if !decode(w, r, &request) {
		return
	}
	if !h.verify(request.Code) {
		problem(w, 400)
		return
	}
	id, err := h.db.CheckIn(r.Context(), request.Code)
	if err != nil {
		respondError(w, err)
		return
	}
	reply(w, 200, map[string]string{"ticket_id": id})
}

func (h *handlers) sign(id string) string {
	m := hmac.New(sha256.New, []byte(h.cfg.TicketSignKey))
	_, _ = m.Write([]byte(id))
	return id + "." + base64.RawURLEncoding.EncodeToString(m.Sum(nil))
}

func (h *handlers) verify(code string) bool {
	id, signature, ok := strings.Cut(code, ".")
	if !ok || !uuidPattern.MatchString(id) {
		return false
	}
	got, err := base64.RawURLEncoding.DecodeString(signature)
	if err != nil {
		return false
	}
	_, want, _ := strings.Cut(h.sign(id), ".")
	expected, _ := base64.RawURLEncoding.DecodeString(want)
	return hmac.Equal(got, expected)
}

type responseLog struct {
	http.ResponseWriter
	status int
}

func (w *responseLog) WriteHeader(status int) {
	if w.status != 0 {
		return
	}
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *responseLog) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.WriteHeader(200)
	}
	return w.ResponseWriter.Write(b)
}

func withRequestLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		logged := &responseLog{ResponseWriter: w}
		next.ServeHTTP(logged, r)
		if logged.status == 0 {
			logged.status = 200
		}
		// Route patterns contain no actual order IDs, ticket codes or query values.
		slog.Info("request", "method", r.Method, "route", r.Pattern, "status", logged.status, "duration_ms", time.Since(start).Milliseconds())
	})
}
