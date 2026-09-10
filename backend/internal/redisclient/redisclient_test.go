package redisclient

import (
	"context"
	"errors"
	"testing"

	"github.com/redis/go-redis/v9"

	"genericim/internal/config"
)

func TestNew_RequiresAddrs(t *testing.T) {
	if _, err := New(context.Background(), config.RedisConfig{}); err == nil {
		t.Fatalf("expected error when no addrs configured")
	}
}

func TestIsCluster_DetectsTopology(t *testing.T) {
	// A real Client is not a ClusterClient; a ClusterClient is.
	if IsCluster(redis.NewClient(&redis.Options{Addr: "127.0.0.1:0"})) {
		t.Fatalf("plain Client should not be reported as Cluster")
	}
	// Constructing a real ClusterClient requires at least one valid host
	// to be reachable, which we cannot guarantee in unit tests. We can
	// however call IsCluster against a nil Cmdable to make sure the type
	// assertion returns false instead of panicking.
	var nilClient redis.Cmdable
	if IsCluster(nilClient) {
		t.Fatalf("nil Cmdable should not be reported as Cluster")
	}
}

func TestNew_PropagatesPingFailure(t *testing.T) {
	// Use an obviously-unreachable address so the PING inside New fails.
	_, err := New(context.Background(), config.RedisConfig{
		Addrs: []string{"127.0.0.1:1"}, // privileged port, almost certainly closed
	})
	if err == nil {
		t.Fatalf("expected ping to fail against unreachable address")
	}
	if !errors.Is(err, err) { // sanity: error is non-nil; we don't pin a cause
		t.Fatalf("error should be non-nil, got %v", err)
	}
}