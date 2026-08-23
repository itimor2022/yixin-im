// 文件用途：定义用户个人邀请码的生成与查询辅助函数。
// 核心逻辑：为每个用户生成指定长度的数字邀请码（首字符 1-9），并提供按码查用户 ID 的工具方法。
// 长度由后台「邀请码位数」配置控制（范围 6-10，默认 6）；同时支持兼容旧版固定 10 位邀请码。

package models

import (
	"crypto/rand"
	"math/big"

	"gorm.io/gorm"
)

// ClampUserInviteCodeLength 将任意输入夹到合法的邀请码位数范围内。
// 传入 ≤ 0 时使用默认值，确保生成/校验逻辑不会因为缺省配置崩溃。
func ClampUserInviteCodeLength(length int) int {
	if length <= 0 {
		return UserInviteCodeDefaultLength
	}
	if length < UserInviteCodeMinLength {
		return UserInviteCodeMinLength
	}
	if length > UserInviteCodeMaxLength {
		return UserInviteCodeMaxLength
	}
	return length
}

// GenerateUserInviteCode 生成长度为 length 的数字邀请码，首字符 1-9。
// length 越界时会自动夹到合法范围（默认 6、最小 6、最大 10）。
// 使用 crypto/rand 避免可预测；冲突由数据库唯一索引保证。
func GenerateUserInviteCode(length int) (string, error) {
	size := ClampUserInviteCodeLength(length)
	const digits = "0123456789"
	buf := make([]byte, size)

	// 首字符：1-9
	first, err := rand.Int(rand.Reader, big.NewInt(9))
	if err != nil {
		return "", err
	}
	buf[0] = digits[1+first.Int64()]

	// 后续 size-1 位：0-9
	for i := 1; i < size; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		buf[i] = digits[n.Int64()]
	}
	return string(buf), nil
}

// IsValidUserInviteCode 校验：必须是「当前配置的合法长度」或「旧版固定 10 位」的纯数字邀请码，首字符 1-9。
// 既保证后台修改位数后新码可用，又兼容历史已生成的 10 位邀请码（避免历史用户/推荐关系失效）。
func IsValidUserInviteCode(code string, length int) bool {
	if code == "" {
		return false
	}
	size := ClampUserInviteCodeLength(length)
	if len(code) != size && len(code) != UserInviteCodeLegacyLength {
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
// length 为后台当前配置的合法位数；旧版固定 10 位始终允许查找。
func FindUserIDByInviteCode(db *gorm.DB, code string, length int) uint64 {
	if !IsValidUserInviteCode(code, length) {
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
