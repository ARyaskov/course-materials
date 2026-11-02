package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/tessera-app/tessera/internal/cache"
	"github.com/tessera-app/tessera/internal/config"
	"github.com/tessera-app/tessera/internal/migrate"
	"github.com/tessera-app/tessera/internal/store"
)

func TestTicketSignature(t *testing.T) {
	h := handlers{cfg: &config.Config{TicketSignKey: "test-only-key"}}
	id := "10000000-0000-4000-8000-000000000001"
	code := h.sign(id)
	if !h.verify(code) {
		t.Fatal("valid ticket rejected")
	}
	for _, invalid := range []string{"", id, code + "x", strings.Replace(code, "10000000", "20000000", 1)} {
		if h.verify(invalid) {
			t.Fatal("forged ticket accepted")
		}
	}
	h.cfg.TicketSignKey = "different-test-only-key"
	if h.verify(code) {
		t.Fatal("ticket from another signing key accepted")
	}
}

func TestInvalidInputDoesNotReachDependencies(t *testing.T) {
	router := Router(nil, nil, &config.Config{TicketSignKey: "test-only-key"})
	cases := []struct{ method, path, body string }{
		{"GET", "/api/v1/events/not-a-uuid/seats", ""},
		{"POST", "/api/v1/orders/not-a-uuid/pay", ""},
		{"POST", "/api/v1/orders", `{}`},
		{"POST", "/api/v1/orders", `{"unknown":true}`},
		{"POST", "/api/v1/orders", `{} {}`},
		{"POST", "/api/v1/orders", `{"event_id":"10000000-0000-4000-8000-000000000001","seat_ids":["abcdef00-0000-4000-8000-000000000001","ABCDEF00-0000-4000-8000-000000000001"]}`},
		{"POST", "/api/v1/checkins", `{"code":"forged"}`},
		{"POST", "/api/v1/checkins", `{"code":"` + strings.Repeat("x", 1<<20) + `"}`},
	}
	for _, c := range cases {
		r := httptest.NewRequest(c.method, c.path, strings.NewReader(c.body))
		w := httptest.NewRecorder()
		router.ServeHTTP(w, r)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("%s %s: status %d", c.method, c.path, w.Code)
		}
	}
}

// Integration tests use a unique schema and remove only their own data.
// Explicit test DSN/Redis address are required; ordinary go test needs no services.
func TestBookingIntegration(t *testing.T) {
	dsn, redisAddr := os.Getenv("TESSERA_TEST_DSN"), os.Getenv("TESSERA_TEST_REDIS_ADDR")
	if dsn == "" || redisAddr == "" {
		t.Skip("set TESSERA_TEST_DSN and TESSERA_TEST_REDIS_ADDR for integration tests")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatal("connect test database failed")
	}
	defer conn.Close(context.Background())
	schema := fmt.Sprintf("tessera_test_%d", time.Now().UnixNano())
	if _, err := conn.Exec(ctx, "CREATE SCHEMA "+pgx.Identifier{schema}.Sanitize()); err != nil {
		t.Fatal(err)
	}
	defer func() {
		cleanup, stop := context.WithTimeout(context.Background(), 5*time.Second)
		defer stop()
		if _, err := conn.Exec(cleanup, "DROP SCHEMA "+pgx.Identifier{schema}.Sanitize()+" CASCADE"); err != nil {
			t.Error("test schema cleanup failed")
		}
	}()
	if _, err := conn.Exec(ctx, "SET search_path TO "+pgx.Identifier{schema}.Sanitize()); err != nil {
		t.Fatal(err)
	}
	for range 2 {
		if err := migrate.Up(ctx, conn); err != nil {
			t.Fatal(err)
		}
	}
	var versions int
	if err := conn.QueryRow(ctx, "SELECT count(*) FROM schema_migrations").Scan(&versions); err != nil || versions != 2 {
		t.Fatalf("migration versions: %d, error: %v", versions, err)
	}
	// Append the isolated search_path without changing credentials or global DB state.
	u, err := url.Parse(dsn)
	if err != nil || (u.Scheme != "postgres" && u.Scheme != "postgresql") {
		t.Fatal("test DSN must be a PostgreSQL URL")
	}
	query := u.Query()
	query.Set("search_path", schema)
	u.RawQuery = query.Encode()
	db, err := store.Open(ctx, u.String(), 8)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	rdb, err := cache.Open(ctx, redisAddr, "", 0)
	if err != nil {
		t.Fatal(err)
	}
	defer rdb.Close()
	if err := rdb.Ping(ctx); err != nil {
		t.Fatal("connect test Redis failed")
	}
	const event = "10000000-0000-4000-8000-000000000001"
	if _, err := conn.Exec(ctx, `INSERT INTO events(id,title,starts_at,venue) VALUES($1,'Test event',now(),'Test venue')`, event); err != nil {
		t.Fatal(err)
	}
	// Unique seat IDs keep Redis keys separate from other runs; they expire by TTL.
	seatIDs := make([]string, 3)
	for i := range seatIDs {
		if err := conn.QueryRow(ctx, `INSERT INTO seats(id,event_id,sector,row_no,seat_no,price)
		 VALUES(gen_random_uuid(),$1,'A',1,$2,12.50) RETURNING id::text`, event, i+1).Scan(&seatIDs[i]); err != nil {
			t.Fatal(err)
		}
	}
	router := Router(db, rdb, &config.Config{TicketSignKey: "test-only-key", HoldTTL: time.Minute})
	request := func(method, path, body string, want int) []byte {
		t.Helper()
		w := httptest.NewRecorder()
		r := httptest.NewRequest(method, path, strings.NewReader(body)).WithContext(ctx)
		router.ServeHTTP(w, r)
		if w.Code != want {
			t.Fatalf("%s %s: status %d, want %d: %s", method, path, w.Code, want, w.Body.String())
		}
		return w.Body.Bytes()
	}
	request("GET", "/api/v1/events", "", 200)
	var seats []store.Seat
	if err := json.Unmarshal(request("GET", "/api/v1/events/"+event+"/seats", "", 200), &seats); err != nil || len(seats) != 3 || !seats[0].Available {
		t.Fatal("initial seats unavailable")
	}
	body := fmt.Sprintf(`{"event_id":%q,"seat_ids":[%q]}`, event, seatIDs[0])
	var order store.Order
	if err := json.Unmarshal(request("POST", "/api/v1/orders", body, 201), &order); err != nil || order.Total != "12.50" {
		t.Fatal("wrong created order")
	}
	request("POST", "/api/v1/orders", body, 409)
	var paid, repeated struct {
		Tickets []store.Ticket `json:"tickets"`
	}
	if err := json.Unmarshal(request("POST", "/api/v1/orders/"+order.ID+"/pay", "", 200), &paid); err != nil || len(paid.Tickets) != 1 {
		t.Fatal("no ticket after payment")
	}
	if err := json.Unmarshal(request("POST", "/api/v1/orders/"+order.ID+"/pay", "", 200), &repeated); err != nil || !reflect.DeepEqual(paid, repeated) {
		t.Fatal("payment retry changed tickets")
	}
	checkin, _ := json.Marshal(map[string]string{"code": paid.Tickets[0].Code})
	request("POST", "/api/v1/checkins", string(checkin), 200)
	request("POST", "/api/v1/checkins", string(checkin), 409)
	request("POST", "/api/v1/orders", body, 409)
	// Competing reservations must never sell the same seat twice.
	results := make(chan error, 8)
	for range 8 {
		go func() {
			_, err := db.CreateOrder(ctx, event, seatIDs[1:2], time.Minute)
			results <- err
		}()
	}
	winners := 0
	for range 8 {
		if err := <-results; err == nil {
			winners++
		} else if !errors.Is(err, store.ErrConflict) {
			t.Fatal(err)
		}
	}
	if winners != 1 {
		t.Fatalf("concurrent reservation winners: %d", winners)
	}
	expired, err := db.CreateOrder(ctx, event, seatIDs[2:], time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := conn.Exec(ctx, "UPDATE orders SET expires_at=now()-interval '1 second' WHERE id=$1", expired.ID); err != nil {
		t.Fatal(err)
	}
	if n, err := db.ExpireOrders(ctx); err != nil || n != 1 {
		t.Fatalf("expired orders: %d, error: %v", n, err)
	}
	request("POST", "/api/v1/orders/"+expired.ID+"/pay", "", 409)
	if _, err := db.CreateOrder(ctx, event, seatIDs[2:], time.Minute); err != nil {
		t.Fatal("expired reservation still blocks seat:", err)
	}
}
