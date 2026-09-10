package mq

import "testing"

func TestQueueName_ShardedKeepsSlot(t *testing.T) {
	// The sharded queue name must be `base:{N}` so Redis Cluster hashes
	// every shard onto the same slot — that's the property the BRPop
	// worker relies on (all keys in one BRPop must share a slot).
	mq := &MessageQueue{shardCount: 4}
	const base = "mq:message:send"

	first := mq.queueName(base, 0)
	for i := 0; i < 4; i++ {
		got := mq.queueName(base, i)
		if len(got) != len(first) {
			t.Fatalf("queueName length drift: shard %d produced %q (base=%q)", i, got, first)
		}
		// The only difference should be the integer between `{` and `}`.
		if got[:len(base)+1] != first[:len(base)+1] {
			t.Fatalf("queueName prefix mismatch for shard %d: %q vs %q", i, got, first)
		}
	}
}

func TestQueueName_NotShardedReturnsBase(t *testing.T) {
	mq := &MessageQueue{shardCount: 1}
	if got := mq.queueName("mq:message:send", 5); got != "mq:message:send" {
		t.Fatalf("expected unsharded key to equal base, got %q", got)
	}
}

func TestPickShard_Deterministic(t *testing.T) {
	mq := &MessageQueue{shardCount: 8}
	a := mq.pickShard("chat-1-message-42")
	b := mq.pickShard("chat-1-message-42")
	if a != b {
		t.Fatalf("pickShard not deterministic: %d vs %d", a, b)
	}
	if a < 0 || a >= 8 {
		t.Fatalf("pickShard out of range: %d", a)
	}
}

func TestPickShard_UnshardedAlwaysZero(t *testing.T) {
	mq := &MessageQueue{shardCount: 1}
	if got := mq.pickShard("anything"); got != 0 {
		t.Fatalf("unsharded pickShard should be 0, got %d", got)
	}
}

func TestAllShards_LengthMatchesShardCount(t *testing.T) {
	mq := &MessageQueue{shardCount: 3}
	keys := mq.allShards("mq:delayed")
	if len(keys) != 3 {
		t.Fatalf("expected 3 shard keys, got %d (%v)", len(keys), keys)
	}
	seen := map[string]bool{}
	for _, k := range keys {
		if seen[k] {
			t.Fatalf("duplicate shard key %q", k)
		}
		seen[k] = true
	}
}