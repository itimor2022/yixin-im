package crossnode

import (
	"context"
	"encoding/json"
	"testing"
)

func TestNoopPublisher_PublishAndSubscribe(t *testing.T) {
	p := NewNoopPublisher("node-test")
	if p.NodeID() != "node-test" {
		t.Fatalf("unexpected NodeID: %s", p.NodeID())
	}

	// Publish is a no-op success path.
	if err := p.Publish(context.Background(), Event{Kind: "test"}); err != nil {
		t.Fatalf("NoopPublisher.Publish should always succeed, got %v", err)
	}

	// Subscribe returns a channel that never produces events.
	ch, cancel, err := p.Subscribe(context.Background())
	if err != nil {
		t.Fatalf("NoopPublisher.Subscribe: %v", err)
	}
	defer cancel()

	select {
	case evt := <-ch:
		t.Fatalf("NoopPublisher.Subscribe should not deliver events, got %+v", evt)
	default:
		// expected: no event pending
	}
}

func TestEventRoundTrip(t *testing.T) {
	// Round-trip an event through JSON to make sure the on-wire format
	// preserves OriginNodeID, payload bytes and target fields.
	original := Event{
		OriginNodeID: "node-A",
		Kind:         "chat_message",
		UserIDs:      []string{"u1", "u2"},
		ChatID:       "c-7",
		BroadcastAll: false,
		Payload:      json.RawMessage(`{"text":"hi","seq":42}`),
	}
	data, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var decoded Event
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if decoded.OriginNodeID != original.OriginNodeID {
		t.Errorf("OriginNodeID: got %q want %q", decoded.OriginNodeID, original.OriginNodeID)
	}
	if decoded.Kind != original.Kind {
		t.Errorf("Kind: got %q want %q", decoded.Kind, original.Kind)
	}
	if len(decoded.UserIDs) != len(original.UserIDs) {
		t.Errorf("UserIDs length: got %d want %d", len(decoded.UserIDs), len(original.UserIDs))
	}
	if string(decoded.Payload) != string(original.Payload) {
		t.Errorf("Payload bytes changed: got %q want %q", decoded.Payload, original.Payload)
	}
}

func TestNoopPublisher_CloseIsIdempotent(t *testing.T) {
	p := NewNoopPublisher("node-close")
	if err := p.Close(); err != nil {
		t.Fatalf("first Close: %v", err)
	}
	if err := p.Close(); err != nil {
		t.Fatalf("second Close should be safe: %v", err)
	}
}