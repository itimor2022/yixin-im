// 文件用途：定义用户个人邀请码的生成与查询辅助函数。
// 核心逻辑：为每个用户生成 10 位数字、首字符 1-9 的邀请码，并提供按码查用户 ID 的工具方法。

package models

import (
	"crypto/rand"
	"math/big"

	"gorm.io/gorm"
)

// UserInviteCodeLength 用户邀请码长度：固定 10 位数字，首位 1-9。
const UserInviteCodeLength = 10

// GenerateUserInviteCode 生成一个 10 位数字邀请码，首字符 1-9。
// 使用 crypto/rand 避免可预测；冲突由数据库唯一索引保证。
func GenerateUserInviteCode() (string, error) {
	const digits = "0123456789"
	buf := make([]byte, UserInviteCodeLength)

	// 首字符：1-9
	first, err := rand.Int(rand.Reader, big.NewInt(9))
	if err != nil {
		return "", err
	}
	buf[0] = digits[1+first.Int64()]

	// 后续 9 位：0-9
	for i := 1; i < UserInviteCodeLength; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		buf[i] = digits[n.Int64()]
	}
	return string(buf), nil
}

// IsValidUserInviteCode 简单校验：必须 10 位数字，首字符不能为 0。
func IsValidUserInviteCode(code string) bool {
	if len(code) != UserInviteCodeLength {
		return false
	}
	if code[0] < '1' || code[0] > '9' {
		return false
	}
	for i := 0; i < len(code); i++ {
		if code[i] < '0' || code[i] > '9' {
			return false
		}
	}
	return true
}

// FindUserIDByInviteCode 根据用户个人邀请码查找用户 ID，未命中返回 0。
// 软删除（deleted_at != NULL）的用户视为不可用作推荐人。
func FindUserIDByInviteCode(db *gorm.DB, code string) uint64 {
	if !IsValidUserInviteCode(code) {
		return 0
	}
	var id uint64
	if err := db.Model(&User{}).
		Select("id").
		Where("invite_code = ? AND deleted_at IS NULL", code).
		Scan(&id).Error; err != nil {
		return 0
	}
	return id
}
