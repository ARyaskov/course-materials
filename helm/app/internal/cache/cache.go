package cache

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
)

// Cache хранит копии броней с TTL. Целостность заказов обеспечивает PostgreSQL.
// Недоступность Redis отражается в readiness и ответе 503 на создание брони.
type Cache struct{ client *redis.Client }

func Open(ctx context.Context, addr, password string, db int) (*Cache, error) {
	c := redis.NewClient(&redis.Options{
		Addr:         addr,
		Password:     password,
		DB:           db,
		DialTimeout:  2 * time.Second,
		ReadTimeout:  500 * time.Millisecond,
		WriteTimeout: 500 * time.Millisecond,
		PoolSize:     20,
	})
	return &Cache{client: c}, nil
}

func (c *Cache) Ping(ctx context.Context) error { return c.client.Ping(ctx).Err() }
func (c *Cache) Close() error                   { return c.client.Close() }

// Hold ставит бронь на место, если оно свободно. Возвращает false,
// если место уже забронировано другим запросом.
func (c *Cache) Hold(ctx context.Context, seatID, orderID string, ttl time.Duration) (bool, error) {
	return c.client.SetNX(ctx, "hold:"+seatID, orderID, ttl).Result()
}
