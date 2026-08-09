// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"encoding/json"
	"fmt"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"strconv"
	"strings"
	"time"
	"genericim/internal/models"
)

type VipEntitlements struct {
	CanCreateGroup         bool   `json:"can_create_group"`
	CanCreateChannel       bool   `json:"can_create_channel"`
	MaxOwnedGroups         int    `json:"max_owned_groups"`
	MaxOwnedChannels       int    `json:"max_owned_channels"`
	MaxGroupMembers        int    `json:"max_group_members"`
	MaxChannelMembers      int    `json:"max_channel_members"`
	MaxPinnedChats         int    `json:"max_pinned_chats"`
	UploadImageLimitMB     int    `json:"upload_image_limit_mb"`
	UploadVideoLimitMB     int    `json:"upload_video_limit_mb"`
	UploadVoiceLimitMB     int    `json:"upload_voice_limit_mb"`
	UploadFileLimitMB      int    `json:"upload_file_limit_mb"`
	CanSetPublicUsername   bool   `json:"can_set_public_username"`
	CanEnableMemberProtect bool   `json:"can_enable_member_protection"`
	Badge                  string `json:"badge"`
	BadgeIcon              string `json:"badge_icon"`
}

type VipStatus struct {
	Level        int8                      `json:"level"`
	LevelName    string                    `json:"level_name"`
	IsActive     bool                      `json:"is_active"`
	Badge        string                    `json:"badge"`
	BadgeIcon    string                    `json:"badge_icon"`
	ExpiredAt    *time.Time                `json:"expired_at"`
	Membership   *models.UserVipMembership `json:"membership,omitempty"`
	Plan         *models.VipPlan           `json:"plan,omitempty"`
	Entitlements VipEntitlements           `json:"entitlements"`
}

type ChatCreationCheck struct {
	Allowed      bool            `json:"allowed"`
	Message      string          `json:"message"`
	Entitlements VipEntitlements `json:"entitlements"`
	Status       VipStatus       `json:"status"`
	OwnedCount   int             `json:"owned_count"`
	OwnedLimit   int             `json:"owned_limit"`
	MaxMembers   int             `json:"max_members"`
}

type VipService struct {
	db *gorm.DB
}

func NewVipService(db *gorm.DB) *VipService {
	return &VipService{db: db}
}

func DefaultVipEntitlements(level int8) VipEntitlements {
	switch level {
	case models.VipLevelVIP:
		return VipEntitlements{
			CanCreateGroup:         true,
			CanCreateChannel:       false,
			MaxOwnedGroups:         5,
			MaxOwnedChannels:       0,
			MaxGroupMembers:        500,
			MaxChannelMembers:      0,
			MaxPinnedChats:         10,
			UploadImageLimitMB:     20,
			UploadVideoLimitMB:     300,
			UploadVoiceLimitMB:     50,
			UploadFileLimitMB:      500,
			CanSetPublicUsername:   false,
			CanEnableMemberProtect: false,
			Badge:                  "VIP",
		}
	case models.VipLevelSVIP:
		return VipEntitlements{
			CanCreateGroup:         true,
			CanCreateChannel:       true,
			MaxOwnedGroups:         20,
			MaxOwnedChannels:       10,
			MaxGroupMembers:        1000,
			MaxChannelMembers:      5000,
			MaxPinnedChats:         20,
			UploadImageLimitMB:     50,
			UploadVideoLimitMB:     1024,
			UploadVoiceLimitMB:     100,
			UploadFileLimitMB:      2048,
			CanSetPublicUsername:   true,
			CanEnableMemberProtect: true,
			Badge:                  "SVIP",
		}
	default:
		return VipEntitlements{
			CanCreateGroup:         true,
			CanCreateChannel:       false,
			MaxOwnedGroups:         3,
			MaxOwnedChannels:       0,
			MaxGroupMembers:        100,
			MaxChannelMembers:      0,
			MaxPinnedChats:         5,
			UploadImageLimitMB:     10,
			UploadVideoLimitMB:     100,
			UploadVoiceLimitMB:     20,
			UploadFileLimitMB:      100,
			CanSetPublicUsername:   false,
			CanEnableMemberProtect: false,
			Badge:                  "",
		}
	}
}

func (s *VipService) FreeEntitlements() VipEntitlements {
	entitlements := DefaultVipEntitlements(models.VipLevelFree)
	if s == nil || s.db == nil {
		return entitlements
	}

	var setting models.SystemSetting
	if err := s.db.Where("`key` = ?", models.SettingVipFreeEntitlements).First(&setting).Error; err != nil {
		return entitlements
	}
	return MergeVipEntitlements(models.VipLevelFree, setting.Value)
}

func (s *VipService) SaveFreeEntitlements(entitlements VipEntitlements) (VipEntitlements, error) {
	entitlements = sanitizeEntitlements(models.VipLevelFree, entitlements)
	if s == nil || s.db == nil {
		return entitlements, nil
	}

	raw, err := json.Marshal(entitlements)
	if err != nil {
		return entitlements, err
	}
	now := time.Now()
	var setting models.SystemSetting
	err = s.db.Where("`key` = ?", models.SettingVipFreeEntitlements).First(&setting).Error
	if err == gorm.ErrRecordNotFound {
		setting = models.SystemSetting{
			Key:       models.SettingVipFreeEntitlements,
			Value:     string(raw),
			Type:      "json",
			Remark:    "普通用户默认权益",
			CreatedAt: now,
			UpdatedAt: now,
		}
		return entitlements, s.db.Create(&setting).Error
	}
	if err != nil {
		return entitlements, err
	}
	return entitlements, s.db.Model(&setting).Updates(map[string]interface{}{
		"value":      string(raw),
		"type":       "json",
		"remark":     "普通用户默认权益",
		"updated_at": now,
	}).Error
}

func sanitizeEntitlements(level int8, entitlements VipEntitlements) VipEntitlements {
	if entitlements.MaxOwnedGroups < 0 {
		entitlements.MaxOwnedGroups = 0
	}
	if entitlements.MaxOwnedChannels < 0 {
		entitlements.MaxOwnedChannels = 0
	}
	if entitlements.MaxGroupMembers < 0 {
		entitlements.MaxGroupMembers = 0
	}
	if entitlements.MaxChannelMembers < 0 {
		entitlements.MaxChannelMembers = 0
	}
	if entitlements.MaxPinnedChats < 0 {
		entitlements.MaxPinnedChats = 0
	}
	if entitlements.UploadImageLimitMB < 0 {
		entitlements.UploadImageLimitMB = 0
	}
	if entitlements.UploadVideoLimitMB < 0 {
		entitlements.UploadVideoLimitMB = 0
	}
	if entitlements.UploadVoiceLimitMB < 0 {
		entitlements.UploadVoiceLimitMB = 0
	}
	if entitlements.UploadFileLimitMB < 0 {
		entitlements.UploadFileLimitMB = 0
	}
	entitlements.Badge = strings.TrimSpace(entitlements.Badge)
	entitlements.BadgeIcon = strings.TrimSpace(entitlements.BadgeIcon)
	if entitlements.Badge == "" && level > models.VipLevelFree {
		entitlements.Badge = LevelName(level)
	}
	if !entitlements.CanCreateGroup {
		entitlements.MaxOwnedGroups = 0
		entitlements.MaxGroupMembers = 0
	}
	if !entitlements.CanCreateChannel {
		entitlements.MaxOwnedChannels = 0
		entitlements.MaxChannelMembers = 0
	}
	return entitlements
}

func LevelName(level int8) string {
	switch level {
	case models.VipLevelVIP:
		return "VIP"
	case models.VipLevelSVIP:
		return "SVIP"
	default:
		return "普通用户"
	}
}

func NormalizeVipLevel(level int8) int8 {
	if level < models.VipLevelFree {
		return models.VipLevelFree
	}
	if level > models.VipLevelSVIP {
		return models.VipLevelSVIP
	}
	return level
}

func hasActiveHigherVipLevel(membership models.UserVipMembership, nextLevel int8, now time.Time) bool {
	return isVipMembershipActive(membership, now) &&
		membership.Level > nextLevel
}

func isVipMembershipActive(membership models.UserVipMembership, now time.Time) bool {
	return membership.Status == models.VipMembershipStatusActive &&
		membership.ExpiredAt.After(now)
}

func MergeVipEntitlements(level int8, raw string) VipEntitlements {
	entitlements := DefaultVipEntitlements(level)
	if strings.TrimSpace(raw) == "" {
		return entitlements
	}
	_ = json.Unmarshal([]byte(raw), &entitlements)
	return sanitizeEntitlements(level, entitlements)
}

func DefaultVipPlanSeeds() []models.VipPlan {
	return []models.VipPlan{
		buildDefaultPlan("vip_month", "VIP 月卡", models.VipLevelVIP, 30, 18, 30, 10, "适合日常建群和文件传输"),
		buildDefaultPlan("vip_year", "VIP 年卡", models.VipLevelVIP, 365, 168, 216, 20, "VIP 权益一年有效"),
		buildDefaultPlan("svip_month", "SVIP 月卡", models.VipLevelSVIP, 30, 38, 58, 30, "适合需要频道和更高容量的用户"),
		buildDefaultPlan("svip_year", "SVIP 年卡", models.VipLevelSVIP, 365, 368, 456, 40, "SVIP 权益一年有效"),
	}
}

func buildDefaultPlan(code, name string, level int8, duration int, price, originalPrice float64, sort int, description string) models.VipPlan {
	benefits, _ := json.Marshal(DefaultVipEntitlements(level))
	now := time.Now()
	return models.VipPlan{
		Code:          code,
		Name:          name,
		Level:         level,
		DurationDays:  duration,
		Price:         price,
		OriginalPrice: originalPrice,
		BenefitsJSON:  string(benefits),
		Description:   description,
		Sort:          sort,
		Enabled:       true,
		CreatedAt:     now,
		UpdatedAt:     now,
	}
}

func (s *VipService) EnsureDefaultPlans() error {
	if s == nil || s.db == nil {
		return nil
	}
	for _, seed := range DefaultVipPlanSeeds() {
		var existing models.VipPlan
		err := s.db.Where("code = ?", seed.Code).First(&existing).Error
		if err == nil {
			continue
		}
		if err != gorm.ErrRecordNotFound {
			return err
		}
		if err := s.db.Create(&seed).Error; err != nil {
			return err
		}
	}
	return nil
}

func (s *VipService) ListEnabledPlans() ([]models.VipPlan, error) {
	var plans []models.VipPlan
	err := s.db.Where("enabled = ?", true).
		Order("sort ASC, id ASC").
		Find(&plans).Error
	return plans, err
}

func (s *VipService) GetStatus(userID uint64) (VipStatus, error) {
	status := VipStatus{
		Level:     models.VipLevelFree,
		LevelName: LevelName(models.VipLevelFree),
		IsActive:  false,
	}
	status.Entitlements = s.FreeEntitlements()
	if s == nil || s.db == nil || userID == 0 {
		return status, nil
	}

	var membership models.UserVipMembership
	err := s.db.Where("user_id = ?", userID).First(&membership).Error
	if err == gorm.ErrRecordNotFound {
		return status, nil
	}
	if err != nil {
		return status, err
	}
	now := time.Now()
	active := isVipMembershipActive(membership, now)
	if !active {
		if membership.Status == models.VipMembershipStatusActive && !membership.ExpiredAt.After(now) {
			_ = s.db.Model(&membership).Updates(map[string]interface{}{
				"status":     models.VipMembershipStatusExpired,
				"updated_at": now,
			}).Error
			membership.Status = models.VipMembershipStatusExpired
		}
		status.Membership = &membership
		return status, nil
	}
	level := NormalizeVipLevel(membership.Level)
	status.Level = level
	status.LevelName = LevelName(level)
	status.IsActive = true
	status.ExpiredAt = &membership.ExpiredAt
	status.Membership = &membership
	status.Entitlements = DefaultVipEntitlements(level)
	status.Badge = status.Entitlements.Badge
	status.BadgeIcon = status.Entitlements.BadgeIcon

	if membership.PlanID != nil && *membership.PlanID > 0 {
		var plan models.VipPlan
		if err := s.db.First(&plan, *membership.PlanID).Error; err == nil {
			status.Plan = &plan
			status.Entitlements = MergeVipEntitlements(level, plan.BenefitsJSON)
			status.Badge = status.Entitlements.Badge
			status.BadgeIcon = status.Entitlements.BadgeIcon
		}
	}
	return status, nil
}

func (s *VipService) CanCreateChat(userID uint64, chatType int8) (ChatCreationCheck, error) {
	status, err := s.GetStatus(userID)
	if err != nil {
		return ChatCreationCheck{}, err
	}
	check := evaluateChatCreation(status, chatType, 0)
	if chatType != 2 && chatType != 3 {
		return check, nil
	}
	if !check.Allowed || check.OwnedLimit <= 0 {
		return check, nil
	}

	var ownedCount int64
	if err := s.db.Model(&models.Chat{}).
		// Dissolved chats retain history by design, but they no longer consume an
		// owned-chat slot. Otherwise a user who reaches the limit can never create
		// another group/channel even after dissolving old ones.
		Where(
			"owner_id = ? AND type = ? AND status <> ? AND deleted_at IS NULL",
			userID,
			chatType,
			models.ChatStatusDissolved,
		).
		Count(&ownedCount).Error; err != nil {
		return check, err
	}
	return evaluateChatCreation(status, chatType, int(ownedCount)), nil
}

func evaluateChatCreation(status VipStatus, chatType int8, ownedCount int) ChatCreationCheck {
	entitlements := status.Entitlements
	check := ChatCreationCheck{
		Allowed:      true,
		Entitlements: entitlements,
		Status:       status,
	}
	if chatType != 2 && chatType != 3 {
		return check
	}
	if chatType == 2 {
		check.OwnedLimit = entitlements.MaxOwnedGroups
		check.MaxMembers = entitlements.MaxGroupMembers
		if !entitlements.CanCreateGroup {
			check.Allowed = false
			check.Message = "开通 VIP 后可创建群聊"
			return check
		}
	} else {
		check.OwnedLimit = entitlements.MaxOwnedChannels
		check.MaxMembers = entitlements.MaxChannelMembers
		if !entitlements.CanCreateChannel {
			check.Allowed = false
			if status.Level >= models.VipLevelVIP {
				check.Message = "开通 SVIP 后可创建频道"
			} else {
				check.Message = "开通 SVIP 后可创建频道"
			}
			return check
		}
	}
	if check.OwnedLimit > 0 {
		check.OwnedCount = ownedCount
		if check.OwnedCount >= check.OwnedLimit {
			check.Allowed = false
			if chatType == 2 {
				check.Message = fmt.Sprintf("当前会员最多可创建 %d 个群聊", check.OwnedLimit)
			} else {
				check.Message = fmt.Sprintf("当前会员最多可创建 %d 个频道", check.OwnedLimit)
			}
			return check
		}
	}
	return check
}

func (s *VipService) EffectiveOwnedChatLimit(userID uint64, chatType int8) int {
	check, err := s.CanCreateChat(userID, chatType)
	if err != nil {
		if chatType == 2 {
			return DefaultVipEntitlements(models.VipLevelFree).MaxOwnedGroups
		}
		if chatType == 3 {
			return DefaultVipEntitlements(models.VipLevelFree).MaxOwnedChannels
		}
		return 0
	}
	return check.OwnedLimit
}

func (s *VipService) PinnedChatLimit(userID uint64) int {
	status, err := s.GetStatus(userID)
	if err != nil {
		return DefaultVipEntitlements(models.VipLevelFree).MaxPinnedChats
	}
	return status.Entitlements.MaxPinnedChats
}

func (s *VipService) UploadLimitBytes(userID uint64, mediaType string) int64 {
	status, err := s.GetStatus(userID)
	entitlements := DefaultVipEntitlements(models.VipLevelFree)
	if err == nil {
		entitlements = status.Entitlements
	}
	limitMB := entitlements.UploadFileLimitMB
	switch mediaType {
	case "image":
		limitMB = entitlements.UploadImageLimitMB
	case "video":
		limitMB = entitlements.UploadVideoLimitMB
	case "voice":
		limitMB = entitlements.UploadVoiceLimitMB
	case "file":
		limitMB = entitlements.UploadFileLimitMB
	}
	if limitMB <= 0 {
		limitMB = DefaultVipEntitlements(models.VipLevelFree).UploadFileLimitMB
	}
	return int64(limitMB) * 1024 * 1024
}

func (s *VipService) PurchaseWithWallet(userID, planID uint64) (*models.VipOrder, VipStatus, error) {
	var order models.VipOrder
	var status VipStatus
	err := s.db.Transaction(func(tx *gorm.DB) error {
		var plan models.VipPlan
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("id = ? AND enabled = ?", planID, true).
			First(&plan).Error; err != nil {
			return fmt.Errorf("会员套餐不存在或已下架")
		}

		var wallet models.Wallet
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("user_id = ?", userID).
			First(&wallet).Error; err != nil {
			if err != gorm.ErrRecordNotFound {
				return err
			}
			wallet = models.Wallet{
				UserID:    userID,
				CreatedAt: time.Now(),
				UpdatedAt: time.Now(),
			}
			if err := tx.Create(&wallet).Error; err != nil {
				return err
			}
		}
		if err := validateVipWalletPurchase(wallet, plan); err != nil {
			return err
		}
		now := time.Now()
		var membership models.UserVipMembership
		err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("user_id = ?", userID).
			First(&membership).Error
		if err != nil && err != gorm.ErrRecordNotFound {
			return err
		}
		if err == nil && hasActiveHigherVipLevel(membership, plan.Level, now) {
			return fmt.Errorf("当前已是更高等级会员，请选择同级或更高级套餐")
		}

		order = models.VipOrder{
			OrderNo:   buildVipOrderNo(now),
			UserID:    userID,
			PlanID:    plan.ID,
			Amount:    plan.Price,
			PayMethod: models.VipPayMethodWallet,
			Status:    models.VipOrderStatusPaid,
			PaidAt:    &now,
			Remark:    "钱包余额购买会员",
			CreatedAt: now,
			UpdatedAt: now,
		}
		if err := tx.Create(&order).Error; err != nil {
			return err
		}
		newBalance := wallet.Balance - plan.Price
		if err := tx.Model(&wallet).Updates(map[string]interface{}{
			"balance":    gorm.Expr("balance - ?", plan.Price),
			"updated_at": now,
		}).Error; err != nil {
			return err
		}
		transaction := models.Transaction{
			UserID:       userID,
			Type:         models.TransactionTypeVipPurchase,
			Amount:       -plan.Price,
			BalanceAfter: newBalance,
			RelatedID:    strconv.FormatUint(order.ID, 10),
			Remark:       "购买" + plan.Name,
			CreatedAt:    now,
		}
		if err := tx.Create(&transaction).Error; err != nil {
			return err
		}
		order.TransactionID = strconv.FormatUint(transaction.ID, 10)
		if err := tx.Model(&order).Update("transaction_id", order.TransactionID).Error; err != nil {
			return err
		}
		return s.upsertMembership(tx, userID, &plan, models.VipPayMethodWallet, "钱包余额购买会员", now)
	})
	if err != nil {
		return nil, status, err
	}
	status, err = s.GetStatus(userID)
	return &order, status, err
}

func validateVipWalletPurchase(wallet models.Wallet, plan models.VipPlan) error {
	if wallet.IsLocked {
		return fmt.Errorf("钱包已锁定，无法购买会员")
	}
	if wallet.Balance < plan.Price {
		return fmt.Errorf("钱包余额不足")
	}
	return nil
}

func (s *VipService) GrantMembership(userID, planID uint64, days int, remark string) (VipStatus, error) {
	var status VipStatus
	err := s.db.Transaction(func(tx *gorm.DB) error {
		var plan models.VipPlan
		if err := tx.Where("id = ?", planID).First(&plan).Error; err != nil {
			return fmt.Errorf("会员套餐不存在")
		}
		if days <= 0 {
			days = plan.DurationDays
		}
		grantPlan := plan
		grantPlan.DurationDays = days
		now := time.Now()
		order := models.VipOrder{
			OrderNo:   buildVipOrderNo(now),
			UserID:    userID,
			PlanID:    plan.ID,
			Amount:    0,
			PayMethod: models.VipPayMethodManual,
			Status:    models.VipOrderStatusPaid,
			PaidAt:    &now,
			Remark:    remark,
			CreatedAt: now,
			UpdatedAt: now,
		}
		if err := tx.Create(&order).Error; err != nil {
			return err
		}
		return s.upsertMembership(tx, userID, &grantPlan, models.VipPayMethodManual, remark, now)
	})
	if err != nil {
		return status, err
	}
	return s.GetStatus(userID)
}

func (s *VipService) CancelMembership(userID uint64, remark string) (VipStatus, error) {
	now := time.Now()
	result := s.db.Model(&models.UserVipMembership{}).
		Where("user_id = ?", userID).
		Updates(map[string]interface{}{
			"status":      models.VipMembershipStatusCanceled,
			"canceled_at": now,
			"remark":      remark,
			"updated_at":  now,
		})
	if result.Error != nil {
		return VipStatus{}, result.Error
	}
	if result.RowsAffected == 0 {
		return VipStatus{}, fmt.Errorf("会员记录不存在")
	}
	return s.GetStatus(userID)
}

func (s *VipService) FreezeMembership(userID uint64, remark string) (VipStatus, error) {
	now := time.Now()
	result := s.db.Model(&models.UserVipMembership{}).
		Where("user_id = ?", userID).
		Where("status <> ?", models.VipMembershipStatusCanceled).
		Updates(map[string]interface{}{
			"status":     models.VipMembershipStatusFrozen,
			"remark":     remark,
			"updated_at": now,
		})
	if result.Error != nil {
		return VipStatus{}, result.Error
	}
	if result.RowsAffected == 0 {
		return VipStatus{}, fmt.Errorf("没有可冻结的会员记录")
	}
	return s.GetStatus(userID)
}

func (s *VipService) UnfreezeMembership(userID uint64, remark string) (VipStatus, error) {
	var membership models.UserVipMembership
	if err := s.db.Where("user_id = ? AND status = ?", userID, models.VipMembershipStatusFrozen).
		First(&membership).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return VipStatus{}, fmt.Errorf("冻结会员记录不存在")
		}
		return VipStatus{}, err
	}
	now := time.Now()
	nextStatus := models.VipMembershipStatusActive
	if !membership.ExpiredAt.After(now) {
		nextStatus = models.VipMembershipStatusExpired
	}
	if err := s.db.Model(&membership).Updates(map[string]interface{}{
		"status":     nextStatus,
		"remark":     remark,
		"updated_at": now,
	}).Error; err != nil {
		return VipStatus{}, err
	}
	return s.GetStatus(userID)
}

func (s *VipService) upsertMembership(tx *gorm.DB, userID uint64, plan *models.VipPlan, source, remark string, now time.Time) error {
	var membership models.UserVipMembership
	err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("user_id = ?", userID).
		First(&membership).Error
	if err != nil && err != gorm.ErrRecordNotFound {
		return err
	}
	startAt := now
	if err == nil && membership.Status == models.VipMembershipStatusActive && membership.ExpiredAt.After(now) && membership.Level >= plan.Level {
		startAt = membership.ExpiredAt
	}
	expiredAt := startAt.AddDate(0, 0, plan.DurationDays)
	planID := plan.ID

	if err == gorm.ErrRecordNotFound {
		membership = models.UserVipMembership{
			UserID:    userID,
			PlanID:    &planID,
			Level:     plan.Level,
			Source:    source,
			Status:    models.VipMembershipStatusActive,
			StartedAt: now,
			ExpiredAt: expiredAt,
			Remark:    remark,
			CreatedAt: now,
			UpdatedAt: now,
		}
		return tx.Create(&membership).Error
	}
	return tx.Model(&membership).Updates(map[string]interface{}{
		"plan_id":     planID,
		"level":       plan.Level,
		"source":      source,
		"status":      models.VipMembershipStatusActive,
		"started_at":  now,
		"expired_at":  expiredAt,
		"canceled_at": nil,
		"remark":      remark,
		"updated_at":  now,
	}).Error
}

func buildVipOrderNo(now time.Time) string {
	return fmt.Sprintf("VIP%s%s", now.Format("20060102150405"), strings.ReplaceAll(uuid.New().String()[:8], "-", ""))
}
