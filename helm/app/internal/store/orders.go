package store

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

var ErrNotFound = errors.New("not found")
var ErrConflict = errors.New("reservation is unavailable")

type Event struct {
	ID       string    `json:"id"`
	Title    string    `json:"title"`
	StartsAt time.Time `json:"starts_at"`
	Venue    string    `json:"venue"`
}

type Seat struct {
	ID        string `json:"id"`
	Sector    string `json:"sector"`
	Row       int    `json:"row_no"`
	Number    int    `json:"seat_no"`
	Price     string `json:"price"`
	Available bool   `json:"available"`
}

type Order struct {
	ID        string    `json:"id"`
	Total     string    `json:"total"`
	ExpiresAt time.Time `json:"expires_at"`
}

type Ticket struct {
	ID     string `json:"id"`
	SeatID string `json:"seat_id"`
	Code   string `json:"code"`
}

func newID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func (d *DB) Events(ctx context.Context) ([]Event, error) {
	rows, err := d.pool.Query(ctx, "SELECT id::text,title,starts_at,venue FROM events ORDER BY starts_at,id LIMIT 100")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Event{}
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.ID, &e.Title, &e.StartsAt, &e.Venue); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (d *DB) Seats(ctx context.Context, eventID string) ([]Seat, error) {
	var exists bool
	if err := d.pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM events WHERE id=$1::uuid)", eventID).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, ErrNotFound
	}
	rows, err := d.pool.Query(ctx, `SELECT s.id::text,s.sector,s.row_no,s.seat_no,s.price::text,
	 NOT EXISTS(SELECT 1 FROM order_seats i JOIN orders o ON o.id=i.order_id
	 WHERE i.seat_id=s.id AND (o.status='paid' OR (o.status='pending' AND o.expires_at>clock_timestamp())))
	 FROM seats s WHERE s.event_id=$1::uuid ORDER BY s.sector,s.row_no,s.seat_no`, eventID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Seat{}
	for rows.Next() {
		var s Seat
		if err := rows.Scan(&s.ID, &s.Sector, &s.Row, &s.Number, &s.Price, &s.Available); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// Seat row locks make PostgreSQL authoritative even if Redis is restarted.
func (d *DB) CreateOrder(ctx context.Context, eventID string, seatIDs []string, ttl time.Duration) (*Order, error) {
	tx, err := d.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(context.Background())
	rows, err := tx.Query(ctx, "SELECT id FROM seats WHERE id=ANY($1::uuid[]) AND event_id=$2::uuid ORDER BY id FOR UPDATE", seatIDs, eventID)
	if err != nil {
		return nil, err
	}
	n := 0
	for rows.Next() {
		n++
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if n != len(seatIDs) {
		return nil, ErrNotFound
	}
	var busy bool
	err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM order_seats i JOIN orders o ON o.id=i.order_id
	 WHERE i.seat_id=ANY($1::uuid[]) AND (o.status='paid' OR (o.status='pending' AND o.expires_at>clock_timestamp())))`, seatIDs).Scan(&busy)
	if err != nil {
		return nil, err
	}
	if busy {
		return nil, ErrConflict
	}
	o := &Order{ID: newID()}
	err = tx.QueryRow(ctx, `INSERT INTO orders(id,event_id,status,total,expires_at)
	 SELECT $1::uuid,$2::uuid,'pending',sum(price),clock_timestamp()+($3 * interval '1 second') FROM seats WHERE id=ANY($4::uuid[])
	 RETURNING total::text,expires_at`, o.ID, eventID, ttl.Seconds(), seatIDs).Scan(&o.Total, &o.ExpiresAt)
	if err != nil {
		return nil, err
	}
	for _, id := range seatIDs {
		if _, err = tx.Exec(ctx, "INSERT INTO order_seats(order_id,seat_id) VALUES($1::uuid,$2::uuid)", o.ID, id); err != nil {
			return nil, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return nil, err
	}
	return o, nil
}

// PayOrder simulates successful payment for the course; no payment provider is called.
func (d *DB) PayOrder(ctx context.Context, orderID string, sign func(string) string) ([]Ticket, error) {
	tx, err := d.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(context.Background())
	rows, err := tx.Query(ctx, `SELECT s.id::text FROM seats s JOIN order_seats i ON i.seat_id=s.id
	 WHERE i.order_id=$1::uuid ORDER BY s.id FOR UPDATE OF s`, orderID)
	if err != nil {
		return nil, err
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			rows.Close()
			return nil, err
		}
		ids = append(ids, id)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	var status string
	var active bool
	err = tx.QueryRow(ctx, "SELECT status,expires_at>clock_timestamp() FROM orders WHERE id=$1::uuid FOR UPDATE", orderID).Scan(&status, &active)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	if status != "paid" {
		if status != "pending" || !active {
			return nil, ErrConflict
		}
		for _, seat := range ids {
			id := newID()
			if _, err = tx.Exec(ctx, "INSERT INTO tickets(id,order_id,seat_id,code) VALUES($1::uuid,$2::uuid,$3::uuid,$4)", id, orderID, seat, sign(id)); err != nil {
				return nil, err
			}
		}
		if _, err = tx.Exec(ctx, "UPDATE orders SET status='paid' WHERE id=$1::uuid", orderID); err != nil {
			return nil, err
		}
	}
	rows, err = tx.Query(ctx, "SELECT id::text,seat_id::text,code FROM tickets WHERE order_id=$1::uuid ORDER BY seat_id", orderID)
	if err != nil {
		return nil, err
	}
	out := []Ticket{}
	for rows.Next() {
		var t Ticket
		if err = rows.Scan(&t.ID, &t.SeatID, &t.Code); err != nil {
			rows.Close()
			return nil, err
		}
		out = append(out, t)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(ctx); err != nil {
		return nil, err
	}
	return out, nil
}

func (d *DB) CheckIn(ctx context.Context, code string) (string, error) {
	var id string
	err := d.pool.QueryRow(ctx, "UPDATE tickets SET checked_in_at=now() WHERE code=$1 AND checked_in_at IS NULL RETURNING id::text", code).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrConflict
	}
	return id, err
}

func (d *DB) ExpireOrders(ctx context.Context) (int64, error) {
	r, err := d.pool.Exec(ctx, "UPDATE orders SET status='expired' WHERE status='pending' AND expires_at<=clock_timestamp()")
	return r.RowsAffected(), err
}
