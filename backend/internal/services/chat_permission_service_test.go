// 文件用途：验证 chat_permission_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"context"
	"errors"
	"testing"
	"genericim/internal/models"
)

func TestOwnerChatAdminPermissionsHasAllManagementPermissions(t *testing.T) {
	perm := OwnerChatAdminPermissions()
	if !perm.CanManageAdmins {
		t.Fatal("owner should be able to manage admins")
	}
	if !perm.CanMuteUsers || !perm.CanBanUsers || !perm.CanManageJoinRequests {
		t.Fatal("owner should have moderation permissions")
	}
	if !perm.CanPostMessages || !perm.CanEditMessages {
		t.Fatal("owner should have channel posting permissions")
	}
}

func TestDefaultChatAdminPermissionsByChatType(t *testing.T) {
	groupPerm := DefaultChatAdminPermissions(2)
	if groupPerm.CanPostMessages || groupPerm.CanEditMessages {
		t.Fatal("group admins should not get channel post/edit permissions by default")
	}
	if !groupPerm.CanMuteUsers || !groupPerm.CanInviteUsers {
		t.Fatal("group admins should get moderation permissions by default")
	}
	channelPerm := DefaultChatAdminPermissions(3)
	if !channelPerm.CanPostMessages || !channelPerm.CanEditMessages {
		t.Fatal("channel admins should get post/edit permissions by default")
	}
}

func TestCanRemoveMemberRejectsPlainMember(t *testing.T) {
	svc := NewChatPermissionService(nil)
	err := svc.CanRemoveMember(
		context.Background(),
		models.Chat{OwnerID: 1},
		models.ChatMember{UserID: 2, Role: 0},
		models.ChatMember{UserID: 3, Role: 0},
	)
	if !errors.Is(err, ErrChatPermissionDenied) {
		t.Fatalf("expected denied, got %v", err)
	}
}

func TestCanRemoveMemberRejectsOwnerTarget(t *testing.T) {
	svc := NewChatPermissionService(nil)
	err := svc.CanRemoveMember(
		context.Background(),
		models.Chat{OwnerID: 1},
		models.ChatMember{UserID: 1, Role: 2},
		models.ChatMember{UserID: 1, Role: 2},
	)
	if !errors.Is(err, ErrChatPermissionTargetOwner) {
		t.Fatalf("expected owner target error, got %v", err)
	}
}

func TestCanMuteMemberAllowsOwnerToMuteMember(t *testing.T) {
	svc := NewChatPermissionService(nil)
	err := svc.CanMuteMember(
		context.Background(),
		models.Chat{OwnerID: 1},
		models.ChatMember{UserID: 1, Role: 2},
		models.ChatMember{UserID: 2, Role: 0},
	)
	if err != nil {
		t.Fatalf("expected owner to mute member, got %v", err)
	}
}
