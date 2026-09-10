// Package redisclient hides the difference between single-node Redis and
// Redis Cluster behind a small factory. The rest of the codebase depends on
// the `redis.Cmdable` interface that go-redis ships for both Client and
// ClusterClient, so business code can call Get/Set/Pipeline/Script.Run
// without caring about which topology it is talking to.
//
// Selection rules (mirroring go-redis/v9 UniversalClient.NewUniversalClient):
//   - 0 Addrs            : no client (the factory returns an error).
//   - 1 Addrs, IsClusterMode=false : single-node Client (the most common case).
//   - 1 Addrs, IsClusterMode=true  : ClusterClient (ElastiCache configuration
//     endpoint style).
//   - 2+ Addrs           : ClusterClient.
//
// In every case the same redis.UniversalClient is returned; tests and
// downstream code just use the Cmdable interface for read/write commands and
// fall back to UniversalClient only when they need Subscribe / PSubscribe /
// PoolStats / Close.
package redisclient

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"genericim/internal/config"
)

// New constructs the right go-redis client for cfg.Redis and verifies the
// connection with a PING before returning. The returned client is the
// UniversalClient interface so callers retain access to Subscribe when needed
// (Hub cross-node fan-out); the cache/mq layers only need Cmdable which is
// satisfied by both Client and ClusterClient.
func New(ctx context.Context, cfg config.RedisConfig) (redis.UniversalClient, error) {
	addrs := cfg.Addrs
	if len(addrs) == 0 {
		return nil, fmt.Errorf("redis.addrs (or legacy redis.addr) must be configured")
	}
	opts := &redis.UniversalOptions{
		Addrs:        addrs,
		Password:     cfg.Password,
		DB:           cfg.DB,
		PoolSize:     cfg.PoolSize,
		MinIdleConns: cfg.MinIdleConns,
		// Always enable the cluster client when the operator explicitly asks
		// for it; otherwise let go-redis auto-detect based on len(Addrs).
		IsClusterMode: cfg.IsClusterMode,
		// Conservative defaults so a single bad node doesn't stall the
		// request for seconds during a partition.
		DialTimeout:  3 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
	}
	client := redis.NewUniversalClient(opts)
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := client.Ping(pingCtx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("redis ping failed (addrs=%v): %w", addrs, err)
	}
	return client, nil
}

// IsCluster reports whether the client is a *redis.ClusterClient. Used by
// call sites that have to make topology-specific decisions (e.g. the Hub
// cross-node publisher — which only makes sense when we actually have
// multiple API nodes, but the underlying Redis mode is independent).
func IsCluster(client redis.Cmdable) bool {
	_, ok := client.(*redis.ClusterClient)
	return ok
}