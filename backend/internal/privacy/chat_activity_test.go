// 文件用途：验证聊天活跃状态隐私策略不会重新引入群回执广播放大。
// 核心逻辑：群聊和频道的已读状态只维护成员游标，私聊仍支持实时回执。

package privacy

import "testing"

func TestCanBroadcastChatActivityForType(t *testing.T) {
	tests := []struct {
		name     string
		kind     chatActivityKind
		chatType int8
		want     bool
	}{
		{name: "private read receipt", kind: chatActivityReadReceipt, chatType: 1, want: true},
		{name: "group read receipt", kind: chatActivityReadReceipt, chatType: 2, want: false},
		{name: "channel read receipt", kind: chatActivityReadReceipt, chatType: 3, want: false},
		{name: "group typing", kind: chatActivityTyping, chatType: 2, want: true},
		{name: "channel typing", kind: chatActivityTyping, chatType: 3, want: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := canBroadcastChatActivityForType(tt.kind, tt.chatType); got != tt.want {
				t.Fatalf(
					"canBroadcastChatActivityForType(kind=%d, chatType=%d)=%v, want %v",
					tt.kind,
					tt.chatType,
					got,
					tt.want,
				)
			}
		})
	}
}
