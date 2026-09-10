// Package crossnode provides the cross-node WebSocket fan-out bridge.
//
// Single-node deployments only need to find connections inside one process,
// which the existing Hub channel pipeline already does. The NoopPublisher
// here lets business code take the same code path on both 1-node and N-node
// deployments without scattering if/else around every call site.
//
// Cluster deployments (cluster.enabled=true) use Redis Pub/Sub as the
// inter-node bus: every API node subscribes to the same channel and stamps
// its nodeID on every event it publishes. Other nodes drop events whose
// OriginNodeID matches their own and otherwise forward the payload to the
// matching local connections.
package crossnode

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"sync/atomic"

	"github.com/redis/go-redis/v9"
)

// Event is one cross-node message. Payload is the raw JSON the Hub would
// otherwise drop into a websocket frame; OriginNodeID is stamped by the
// publisher and used to drop our own echoed events.
type Event struct {
	OriginNodeID string          `json:"node"`
	Kind         string          `json:"kind"`
	UserIDs      []string        `json:"user_ids,omitempty"`
	ChatID       string          `json:"chat_id,omitempty"`
	BroadcastAll bool            `json:"all,omitempty"`
	Payload      json.RawMessage `json:"payload"`
}

// Publisher abstracts the two implementations so the Hub can be wired in
// without knowing whether we're on a single node or in a 3-node cluster.
//
// Publish is fire-and-forget; the caller does not block on subscriber
// delivery. Subscribe returns a channel that the Hub drains in its existing
// broadcast loop, plus a cancel function that should be invoked at shutdown.
type Publisher interface {
	Publish(ctx context.Context, evt Event) error
	Subscribe(ctx context.Context) (<-chan Event, func(), error)
	NodeID() string
	Close() error
}

// NoopPublisher is the single-node implementation. Publish always succeeds
// without sending anything; Subscribe never produces an event. Constructing
// one is cheap; NewNoopPublisher returns a fresh instance so tests can verify
// the wire-up without touching real Redis.
type NoopPublisher struct {
	nodeID string
}

// NewNoopPublisher returns a Publisher that does nothing on Publish and
// never produces events on Subscribe. Used when cluster.enabled=false.
func NewNoopPublisher(nodeID string) *NoopPublisher {
	return &NoopPublisher{nodeID: nodeID}
}

func (n *NoopPublisher) Publish(ctx context.Context, evt Event) error {
	// single-node deployments don't need to publish anywhere; the Hub's
	// own SendToXxx already pushes to the local client set.
	return nil
}

func (n *NoopPublisher) Subscribe(ctx context.Context) (<-chan Event, func(), error) {
	ch := make(chan Event)
	cancel := func() { close(ch) }
	return ch, cancel, nil
}

func (n *NoopPublisher) NodeID() string { return n.nodeID }
func (n *NoopPublisher) Close() error    { return nil }

// RedisPublisher implements the multi-node bridge. It uses a single Redis
// client (the one the cache/mq layers already share, hence the interface
// parameter). On Cluster this means Publish routes to the slot owning the
// configured channel name; Subscribe sees events from every shard via the
// cluster-wide pub/sub channel.
type RedisPublisher struct {
	client  redis.UniversalClient
	nodeID  string
	channel string

	mu     sync.Mutex
	subs   []*redis.PubSub
	closed atomic.Bool
}

// NewRedisPublisher wires up a Publisher backed by Redis Pub/Sub.
// `client` is the universal client (works for both standalone and Cluster
// Redis). `channel` is the shared Pub/Sub channel name — choose a stable
// value across all API nodes ("ws:node:fanout" by default).
func NewRedisPublisher(client redis.UniversalClient, nodeID, channel string) (*RedisPublisher, error) {
	if client == nil {
		return nil, fmt.Errorf("crossnode: redis client is nil")
	}
	if nodeID == "" {
		return nil, fmt.Errorf("crossnode: nodeID is required")
	}
	if channel == "" {
		channel = "ws:node:fanout"
	}
	return &RedisPublisher{
		client:  client,
		nodeID:  nodeID,
		channel: channel,
	}, nil
}

func (r *RedisPublisher) NodeID() string { return r.nodeID }

// Channel returns the configured Pub/Sub channel name. Exposed for tests
// and admin tooling (e.g. listing subscribers on the channel).
func (r *RedisPublisher) Channel() string { return r.channel }

func (r *RedisPublisher) Publish(ctx context.Context, evt Event) error {
	if r.closed.Load() {
		return fmt.Errorf("crossnode: publisher is closed")
	}
	evt.OriginNodeID = r.nodeID
	data, err := json.Marshal(evt)
	if err != nil {
		return fmt.Errorf("crossnode: marshal event: %w", err)
	}
	if err := r.client.Publish(ctx, r.channel, data).Err(); err != nil {
		return fmt.Errorf("crossnode: redis publish: %w", err)
	}
	return nil
}

// Subscribe attaches a fresh subscription to the shared channel and returns
// a channel of Event values plus a cancel function that closes the
// subscription. Multiple Subscribe calls are allowed so the Hub can be
// re-created (e.g. across graceful restarts) without leaking goroutines.
func (r *RedisPublisher) Subscribe(ctx context.Context) (<-chan Event, func(), error) {
	if r.closed.Load() {
		return nil, nil, fmt.Errorf("crossnode: publisher is closed")
	}
	subCtx, cancel := context.WithCancel(ctx)
	pubsub := r.client.Subscribe(subCtx, r.channel)
	// Wait for subscription confirmation so the caller can rely on the first
	// real message arriving on the returned channel. Without this the Hub
	// would briefly miss events that arrive between Subscribe and the
	// subscription becoming active.
	if _, err := pubsub.Receive(subCtx); err != nil {
		cancel()
		_ = pubsub.Close()
		return nil, nil, fmt.Errorf("crossnode: redis subscribe: %w", err)
	}

	r.mu.Lock()
	r.subs = append(r.subs, pubsub)
	r.mu.Unlock()

	out := make(chan Event, 256)
	go func() {
		defer close(out)
		ch := pubsub.Channel()
		for {
			select {
			case <-subCtx.Done():
				return
			case msg, ok := <-ch:
				if !ok {
					return
				}
				var evt Event
				if err := json.Unmarshal([]byte(msg.Payload), &evt); err != nil {
					log.Printf("[crossnode] invalid event payload: %v", err)
					continue
				}
				// Drop our own echoed events immediately.
				if evt.OriginNodeID == r.nodeID {
					continue
				}
				select {
				case out <- evt:
				case <-subCtx.Done():
					return
				default:
					// Slow consumer — record once and skip rather than block.
					log.Printf("[crossnode] subscriber slow, dropping event kind=%s", evt.Kind)
				}
			}
		}
	}()

	cancelThis := func() {
		cancel()
		_ = pubsub.Close()
	}
	return out, cancelThis, nil
}

func (r *RedisPublisher) Close() error {
	if !r.closed.CompareAndSwap(false, true) {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, s := range r.subs {
		_ = s.Close()
	}
	r.subs = nil
	return nil
}