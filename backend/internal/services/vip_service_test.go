// 文件用途：验证 vip_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"testing"
	"time"
	"genericim/internal/models"
)

func TestMergeVipEntitlementsKeepsDefaultsWhenRawIsInvalid(t *testing.T) {
	got := MergeVipEntitlements(models.VipLevelSVIP, "{")
	if !got.CanCreateGroup || !got.CanCreateChannel {
		t.Fatal("SVIP should keep default group and channel creation rights")
	}
	if got.Badge != "SVIP" {
		t.Fatalf("expected SVIP badge, got %q", got.Badge)
	}
}

func TestMergeVipEntitlementsAppliesBackendOverrides(t *testing.T) {
	got := MergeVipEntitlements(models.VipLevelVIP, `{ 		"can_create_group": true, "can_create_channel": true, "max_owned_groups": 8, "max_owned_channels": 2, "max_group_members": 600, "max_channel_members": 1200, "max_pinned_chats": 12, "upload_image_limit_mb": 30, "upload_video_limit_mb": 500, "upload_voice_limit_mb": 60, "upload_file_limit_mb": 800, "can_set_public_username": true, "can_enable_member_protection": true, "badge": "VIP Pro", "badge_icon": " /uploads/vip/badges/vip.png " 	}`)
	if !got.CanCreateChannel || got.MaxOwnedGroups != 8 || got.MaxOwnedChannels != 2 {
		t.Fatalf("backend entitlement overrides were not applied: %+v", got)
	}
	if got.UploadFileLimitMB != 800 || !got.CanSetPublicUsername || !got.CanEnableMemberProtect {
		t.Fatalf("expected extended entitlement overrides, got %+v", got)
	}
	if got.Badge != "VIP Pro" {
		t.Fatalf("expected custom badge, got %q", got.Badge)
	}
	if got.BadgeIcon != "/uploads/vip/badges/vip.png" {
		t.Fatalf("expected custom badge icon to be trimmed, got %q", got.BadgeIcon)
	}
}

func TestHasActiveHigherVipLevel(t *testing.T) {
	now := time.Date(2026, 6, 24, 12, 0, 0, 0, time.UTC)
	tests := []struct {
		name       string
		membership models.UserVipMembership
		nextLevel  int8
		want       bool
	}{
		{
			name: "blocks active svip downgrade to vip",
			membership: models.UserVipMembership{
				Level:     models.VipLevelSVIP,
				Status:    models.VipMembershipStatusActive,
				ExpiredAt: now.Add(24 * time.Hour),
			},
			nextLevel: models.VipLevelVIP,
			want:      true,
		},
		{
			name: "allows same level renewal",
			membership: models.UserVipMembership{
				Level:     models.VipLevelSVIP,
				Status:    models.VipMembershipStatusActive,
				ExpiredAt: now.Add(24 * time.Hour),
			},
			nextLevel: models.VipLevelSVIP,
			want:      false,
		},
		{
			name: "allows expired higher level",
			membership: models.UserVipMembership{
				Level:     models.VipLevelSVIP,
				Status:    models.VipMembershipStatusActive,
				ExpiredAt: now.Add(-time.Hour),
			},
			nextLevel: models.VipLevelVIP,
			want:      false,
		},
		{
			name: "allows canceled higher level",
			membership: models.UserVipMembership{
				Level:     models.VipLevelSVIP,
				Status:    models.VipMembershipStatusCanceled,
				ExpiredAt: now.Add(24 * time.Hour),
			},
			nextLevel: models.VipLevelVIP,
			want:      false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := hasActiveHigherVipLevel(tt.membership, tt.nextLevel, now)
			if got != tt.want {
				t.Fatalf("expected %v, got %v", tt.want, got)
			}
		})
	}
}

func TestIsVipMembershipActiveRejectsInactiveStates(t *testing.T) {
	now := time.Date(2026, 6, 24, 12, 0, 0, 0, time.UTC)
	tests := []struct {
		name       string
		membership models.UserVipMembership
		want       bool
	}{
		{
			name: "active and not expired",
			membership: models.UserVipMembership{
				Status:    models.VipMembershipStatusActive,
				ExpiredAt: now.Add(time.Hour),
			},
			want: true,
		},
		{
			name: "active but expired",
			membership: models.UserVipMembership{
				Status:    models.VipMembershipStatusActive,
				ExpiredAt: now.Add(-time.Hour),
			},
		},
		{
			name: "frozen with future expiry",
			membership: models.UserVipMembership{
				Status:    models.VipMembershipStatusFrozen,
				ExpiredAt: now.Add(time.Hour),
			},
		},
		{
			name: "canceled with future expiry",
			membership: models.UserVipMembership{
				Status:    models.VipMembershipStatusCanceled,
				ExpiredAt: now.Add(time.Hour),
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isVipMembershipActive(tt.membership, now)
			if got != tt.want {
				t.Fatalf("expected %v, got %v", tt.want, got)
			}
		})
	}
}

func TestEvaluateChatCreationCoversVipBoundaries(t *testing.T) {
	tests := []struct {
		name       string
		status     VipStatus
		chatType   int8
		ownedCount int
		want       ChatCreationCheck
		wantMsg    string
	}{
		{
			name:     "free user can create group within default quota",
			status:   testVipStatus(models.VipLevelFree, false),
			chatType: 2,
			want: ChatCreationCheck{
				Allowed:    true,
				OwnedLimit: 3,
				MaxMembers: 100,
				OwnedCount: 2,
			},
			ownedCount: 2,
		},
		{
			name:     "free user cannot create channel",
			status:   testVipStatus(models.VipLevelFree, false),
			chatType: 3,
			want: ChatCreationCheck{
				Allowed:    false,
				OwnedLimit: 0,
				MaxMembers: 0,
			},
			wantMsg: "开通 SVIP 后可创建频道",
		},
		{
			name:       "free group creation stops at limit",
			status:     testVipStatus(models.VipLevelFree, false),
			chatType:   2,
			ownedCount: 3,
			want: ChatCreationCheck{
				Allowed:    false,
				OwnedLimit: 3,
				MaxMembers: 100,
				OwnedCount: 3,
			},
			wantMsg: "当前会员最多可创建 3 个群聊",
		},
		{
			name:     "vip can create group",
			status:   testVipStatus(models.VipLevelVIP, true),
			chatType: 2,
			want: ChatCreationCheck{
				Allowed:    true,
				OwnedLimit: 5,
				MaxMembers: 500,
				OwnedCount: 4,
			},
			ownedCount: 4,
		},
		{
			name:     "vip cannot create channel",
			status:   testVipStatus(models.VipLevelVIP, true),
			chatType: 3,
			want: ChatCreationCheck{
				Allowed:    false,
				OwnedLimit: 0,
				MaxMembers: 0,
			},
			wantMsg: "开通 SVIP 后可创建频道",
		},
		{
			name:     "svip can create channel",
			status:   testVipStatus(models.VipLevelSVIP, true),
			chatType: 3,
			want: ChatCreationCheck{
				Allowed:    true,
				OwnedLimit: 10,
				MaxMembers: 5000,
				OwnedCount: 3,
			},
			ownedCount: 3,
		},
		{
			name:       "vip group creation stops at limit",
			status:     testVipStatus(models.VipLevelVIP, true),
			chatType:   2,
			ownedCount: 5,
			want: ChatCreationCheck{
				Allowed:    false,
				OwnedLimit: 5,
				MaxMembers: 500,
				OwnedCount: 5,
			},
			wantMsg: "当前会员最多可创建 5 个群聊",
		},
		{
			name:       "svip channel creation stops at limit",
			status:     testVipStatus(models.VipLevelSVIP, true),
			chatType:   3,
			ownedCount: 10,
			want: ChatCreationCheck{
				Allowed:    false,
				OwnedLimit: 10,
				MaxMembers: 5000,
				OwnedCount: 10,
			},
			wantMsg: "当前会员最多可创建 10 个频道",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := evaluateChatCreation(tt.status, tt.chatType, tt.ownedCount)
			if got.Allowed != tt.want.Allowed ||
				got.OwnedLimit != tt.want.OwnedLimit ||
				got.MaxMembers != tt.want.MaxMembers ||
				got.OwnedCount != tt.want.OwnedCount ||
				got.Message != tt.wantMsg {
				t.Fatalf("unexpected check:\n got: %+v\nwant: %+v message=%q", got, tt.want, tt.wantMsg)
			}
		})
	}
}

func TestValidateVipWalletPurchase(t *testing.T) {
	plan := models.VipPlan{Price: 18}
	tests := []struct {
		name    string
		wallet  models.Wallet
		wantErr string
	}{
		{
			name:   "allows exact balance",
			wallet: models.Wallet{Balance: 18},
		},
		{
			name:    "rejects insufficient balance",
			wallet:  models.Wallet{Balance: 17.99},
			wantErr: "钱包余额不足",
		},
		{
			name:    "rejects locked wallet",
			wallet:  models.Wallet{Balance: 100, IsLocked: true},
			wantErr: "钱包已锁定，无法购买会员",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateVipWalletPurchase(tt.wallet, plan)
			if tt.wantErr == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			if err == nil || err.Error() != tt.wantErr {
				t.Fatalf("expected %q, got %v", tt.wantErr, err)
			}
		})
	}
}

func testVipStatus(level int8, active bool) VipStatus {
	level = NormalizeVipLevel(level)
	return VipStatus{
		Level:        level,
		LevelName:    LevelName(level),
		IsActive:     active,
		Badge:        DefaultVipEntitlements(level).Badge,
		Entitlements: DefaultVipEntitlements(level),
	}
}
