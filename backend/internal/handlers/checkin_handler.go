package handlers

import (
	"fmt"
	"time"

	"genericim/internal/middleware"
	"genericim/internal/models"
	"genericim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type CheckinHandler struct {
	db *gorm.DB
}

func NewCheckinHandler(db *gorm.DB) *CheckinHandler {
	return &CheckinHandler{db: db}
}

// DoCheckin POST /checkin — 用户签到
func (h *CheckinHandler) DoCheckin(c *gin.Context) {
	userID := middleware.GetUserID(c)
	today := time.Now().Truncate(24 * time.Hour)

	var existing models.UserCheckin
	err := h.db.Where("user_id = ? AND checkin_at = ?", userID, today).First(&existing).Error
	if err == nil {
		// 今天已签到，直接返回日历
		h.respondCalendar(c, userID, today)
		return
	}

	checkin := models.UserCheckin{
		UserID:    userID,
		CheckinAt: today,
		CreatedAt: time.Now(),
	}
	if err := h.db.Create(&checkin).Error; err != nil {
		response.Error(c, 500, "签到失败")
		return
	}
	h.respondCalendar(c, userID, today)
}

// GetCalendar GET /checkin/calendar?month=2026-08 — 获取签到日历
func (h *CheckinHandler) GetCalendar(c *gin.Context) {
	userID := middleware.GetUserID(c)
	month := c.Query("month")
	if len(month) != 7 {
		month = time.Now().Format("2006-01")
	}
	parsed, err := time.Parse("2006-01", month)
	if err != nil {
		response.Error(c, 400, "月份格式错误")
		return
	}
	h.respondCalendar(c, userID, parsed)
}

func (h *CheckinHandler) respondCalendar(c *gin.Context, userID string, ref time.Time) {
	month := ref.Format("2006-01")
	start := time.Date(ref.Year(), ref.Month(), 1, 0, 0, 0, 0, time.Local)
	end := start.AddDate(0, 1, 0)

	var records []models.UserCheckin
	h.db.Where("user_id = ? AND checkin_at >= ? AND checkin_at < ?", userID, start, end).Find(&records)

	checkedDays := make([]string, 0, len(records))
	today := time.Now().Truncate(24 * time.Hour)
	checkedToday := false
	for _, r := range records {
		day := r.CheckinAt.Format("2006-01-02")
		checkedDays = append(checkedDays, day)
		if r.CheckinAt.Equal(today) {
			checkedToday = true
		}
	}

	// 累计签到总天数
	var totalDays int64
	h.db.Model(&models.UserCheckin{}).Where("user_id = ?", userID).Count(&totalDays)

	// 连续签到天数
	continuousDays := h.calcContinuous(userID, today)

	response.Success(c, gin.H{
		"month":           month,
		"checked_days":    checkedDays,
		"total_days":      totalDays,
		"continuous_days": continuousDays,
		"checked_today":   checkedToday,
	})
}

func (h *CheckinHandler) calcContinuous(userID string, today time.Time) int {
	days := 0
	current := today
	for {
		var count int64
		h.db.Model(&models.UserCheckin{}).
			Where("user_id = ? AND checkin_at = ?", userID, current).
			Count(&count)
		if count == 0 {
			break
		}
		days++
		current = current.AddDate(0, 0, -1)
	}
	return days
}

// AdminListCheckins GET /admin/checkins — 后台查询签到记录
func (h *CheckinHandler) AdminListCheckins(c *gin.Context) {
	page := 1
	pageSize := 20
	if p := c.Query("page"); p != "" {
		if v, err := parseInt(p); err == nil && v > 0 {
			page = v
		}
	}
	if ps := c.Query("page_size"); ps != "" {
		if v, err := parseInt(ps); err == nil && v > 0 && v <= 100 {
			pageSize = v
		}
	}

	query := h.db.Model(&models.UserCheckin{})
	if uid := c.Query("user_id"); uid != "" {
		query = query.Where("user_id = ?", uid)
	}
	if date := c.Query("date"); date != "" {
		query = query.Where("DATE(checkin_at) = ?", date)
	}

	var total int64
	query.Count(&total)

	var records []models.UserCheckin
	query.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&records)

	type CheckinRow struct {
		ID        uint64 `json:"id"`
		UserID    string `json:"user_id"`
		Username  string `json:"username"`
		Nickname  string `json:"nickname"`
		CheckinAt string `json:"checkin_at"`
		CreatedAt string `json:"created_at"`
	}
	rows := make([]CheckinRow, 0, len(records))
	for _, r := range records {
		row := CheckinRow{
			ID:        r.ID,
			UserID:    r.UserID,
			CheckinAt: r.CheckinAt.Format("2006-01-02 15:04:05"),
			CreatedAt: r.CreatedAt.Format("2006-01-02 15:04:05"),
		}
		var u models.User
		if err := h.db.Select("username, nickname").Where("uuid = ?", r.UserID).First(&u).Error; err == nil {
			row.Username = u.Username
			row.Nickname = u.Nickname
		}
		rows = append(rows, row)
	}

	response.Success(c, gin.H{
		"total":   total,
		"page":    page,
		"records": rows,
	})
}

func parseInt(s string) (int, error) {
	v := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0, fmt.Errorf("invalid")
		}
		v = v*10 + int(c-'0')
	}
	return v, nil
}
