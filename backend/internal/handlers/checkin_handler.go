package handlers

import (
	"strconv"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// CheckinHandler 签到处理器
type CheckinHandler struct {
	db *gorm.DB
}

func NewCheckinHandler(db *gorm.DB) *CheckinHandler {
	return &CheckinHandler{db: db}
}

// resolveUserID 根据登录态 user_id(uuid) 查出数值 ID
func (h *CheckinHandler) resolveUserID(c *gin.Context) (uint64, bool) {
	uuid := c.GetString("user_id")
	if uuid == "" {
		return 0, false
	}
	var u models.User
	if err := h.db.Select("id").Where("uuid = ?", uuid).First(&u).Error; err != nil {
		return 0, false
	}
	return u.ID, true
}

// dateOnly 取当天 0 点（本地时区）
func dateOnly(t time.Time) time.Time {
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, t.Location())
}

// DoCheckin 执行签到 POST /api/v1/checkin
func (h *CheckinHandler) DoCheckin(c *gin.Context) {
	userID, ok := h.resolveUserID(c)
	if !ok {
		response.Unauthorized(c, "未登录")
		return
	}

	now := time.Now()
	today := dateOnly(now)

	err := h.db.Transaction(func(tx *gorm.DB) error {
		// 插入签到记录，重复则忽略
		rec := models.UserCheckin{UserID: userID, CheckinDate: today, CreatedAt: now}
		res := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&rec)
		if res.Error != nil {
			return res.Error
		}
		alreadyChecked := res.RowsAffected == 0

		// 读取/初始化统计
		var stat models.UserCheckinStat
		errStat := tx.Where("user_id = ?", userID).First(&stat).Error
		if errStat == gorm.ErrRecordNotFound {
			stat = models.UserCheckinStat{UserID: userID, CreatedAt: now, UpdatedAt: now}
		} else if errStat != nil {
			return errStat
		}

		if alreadyChecked {
			return nil // 今天已签到，统计不变
		}

		// 计算连续天数
		continuous := 1
		if stat.LastCheckinDate != nil {
			last := dateOnly(*stat.LastCheckinDate)
			diff := int(today.Sub(last).Hours() / 24)
			if diff == 1 {
				continuous = stat.ContinuousDays + 1
			} else if diff == 0 {
				continuous = stat.ContinuousDays // 理论不会进这里
			} else {
				continuous = 1
			}
		}
		stat.TotalDays = stat.TotalDays + 1
		stat.ContinuousDays = continuous
		td := today
		stat.LastCheckinDate = &td
		stat.UpdatedAt = now

		return tx.Save(&stat).Error
	})
	if err != nil {
		response.ServerError(c, "签到失败: " + err.Error())
		return
	}

	// 返回最新统计
	var stat models.UserCheckinStat
	h.db.Where("user_id = ?", userID).First(&stat)
	response.SuccessWithMessage(c, "签到成功", gin.H{
		"total_days":      stat.TotalDays,
		"continuous_days": stat.ContinuousDays,
		"checked_today":   true,
	})
}

// GetCalendar 日历 + 统计 GET /api/v1/checkin/calendar?month=2026-06
// func (h *CheckinHandler) GetCalendar(c *gin.Context) {
// 	userID, ok := h.resolveUserID(c)
// 	if !ok {
// 		response.Unauthorized(c, "未登录")
// 		return
// 	}

// 	monthStr := c.Query("month")
// 	var first time.Time
// 	if monthStr != "" {
// 		t, err := time.ParseInLocation("2006-01", monthStr, time.Local)
// 		if err != nil {
// 			response.BadRequest(c, "month 格式应为 2006-01")
// 			return
// 		}
// 		first = t
// 	} else {
// 		now := time.Now()
// 		first = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)
// 	}
// 	last := first.AddDate(0, 1, 0)

// 	var recs []models.UserCheckin
// 	h.db.Where("user_id = ? AND checkin_date >= ? AND checkin_date < ?", userID, first, last).
// 		Order("checkin_date ASC").Find(&recs)

// 	days := make([]string, 0, len(recs))
// 	for _, r := range recs {
// 		days = append(days, r.CheckinDate.Format("2006-01-02"))
// 	}

// 	var stat models.UserCheckinStat
// 	h.db.Where("user_id = ?", userID).First(&stat)

// 	// 今天是否已签到
// 	today := dateOnly(time.Now())
// 	var cnt int64
// 	h.db.Model(&models.UserCheckin{}).Where("user_id = ? AND checkin_date = ?", userID, today).Count(&cnt)

// 	response.Success(c, gin.H{
// 		"month":           first.Format("2006-01"),
// 		"checked_days":    days,
// 		"total_days":      stat.TotalDays,
// 		"continuous_days": stat.ContinuousDays,
// 		"checked_today":   cnt > 0,
// 	})
// }
// GetCalendar 日历 + 统计 GET /api/v1/checkin/calendar?month=2026-06
func (h *CheckinHandler) GetCalendar(c *gin.Context) {
    userID, ok := h.resolveUserID(c)
    if !ok {
        response.Unauthorized(c, "未登录")
        return
    }

    monthStr := c.Query("month")
    var first time.Time
    if monthStr != "" {
        t, err := time.ParseInLocation("2006-01", monthStr, time.Local)
        if err != nil {
            response.BadRequest(c, "month 格式应为 2006-01")
            return
        }
        first = t
    } else {
        now := time.Now()
        first = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)
    }
    last := first.AddDate(0, 1, 0)

    // ======= 🌟 核心修改地方：直接让 MySQL 吐出格式化好的字符串数组 =======
    var days []string
    h.db.Model(&models.UserCheckin{}).
        Where("user_id = ? AND checkin_date >= ? AND checkin_date < ?", userID, first, last).
        Order("checkin_date ASC").
        Pluck("DATE_FORMAT(checkin_date, '%Y-%m-%d')", &days)
    // ===================================================================

    var stat models.UserCheckinStat
    h.db.Where("user_id = ?", userID).First(&stat)

    // 今天是否已签到 (保持不动)
    today := dateOnly(time.Now())
    var cnt int64
    h.db.Model(&models.UserCheckin{}).Where("user_id = ? AND checkin_date = ?", userID, today).Count(&cnt)

    response.Success(c, gin.H{
        "month":           first.Format("2006-01"),
        "checked_days":    days, // 此时 days 里面就是标准的 ["2026-06-01", "2026-06-02"] 字符串了
        "total_days":      stat.TotalDays,
        "continuous_days": stat.ContinuousDays,
        "checked_today":   cnt > 0,
    })
}
// ==================== 后台 ====================

// AdminListCheckins 后台签到记录 GET /admin/checkins/list
func (h *CheckinHandler) AdminListCheckins(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 200 {
		pageSize = 20
	}

	baseQuery := h.db.Table("user_checkins").
		Joins("LEFT JOIN users u ON u.id = user_checkins.user_id AND u.deleted_at IS NULL")

	if kw := c.Query("keyword"); kw != "" {
		like := "%" + kw + "%"
		baseQuery = baseQuery.Where("u.username LIKE ? OR u.nickname LIKE ?", like, like)
	}
	if d := c.Query("date"); d != "" {
		baseQuery = baseQuery.Where("user_checkins.checkin_date = ?", d)
	}

	var total int64
	if err := baseQuery.Count(&total).Error; err != nil {
		response.ServerError(c, "查询签到记录失败")
		return
	}

	type adminCheckinRow struct {
		ID          uint64    `json:"id" gorm:"column:id"`
		UserID      uint64    `json:"user_id" gorm:"column:user_id"`
		CheckinDate string    `json:"checkin_date" gorm:"column:checkin_date"`
		CreatedAt   time.Time `json:"created_at" gorm:"column:created_at"`
		UUID        string    `json:"uuid" gorm:"column:uuid"`
		Username    string    `json:"username" gorm:"column:username"`
		Nickname    string    `json:"nickname" gorm:"column:nickname"`
		Avatar      string    `json:"avatar" gorm:"column:avatar"`
	}

	var rows []adminCheckinRow
	if total > 0 {
		if err := baseQuery.
			Select(`
				user_checkins.id,
				user_checkins.user_id,
				DATE_FORMAT(user_checkins.checkin_date, '%Y-%m-%d') AS checkin_date,
				user_checkins.created_at,
				u.uuid,
				u.username,
				u.nickname,
				u.avatar
			`).
			Order("user_checkins.created_at DESC").
			Offset((page - 1) * pageSize).
			Limit(pageSize).
			Scan(&rows).Error; err != nil {
			response.ServerError(c, "查询签到记录失败")
			return
		}
	}

	response.SuccessWithPage(c, rows, total, page, pageSize)
}
