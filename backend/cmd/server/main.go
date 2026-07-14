package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	gopprof "net/http/pprof"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/captchastore"
	"gaoranim/internal/config"
	"gaoranim/internal/handlers"
	"gaoranim/internal/middleware"
	"gaoranim/internal/models"
	"gaoranim/internal/mq"
	"gaoranim/internal/services"
	"gaoranim/internal/storage"
	"gaoranim/internal/ws"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"gaoranim/internal/metrics"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func main() {
	// 1. 加载配置
	cfg, err := config.Load("config.yaml")
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// 2. 初始化MySQL
	mysqlDB, err := initMySQL(cfg.MySQL, cfg.Server.Mode)
	if err != nil {
		log.Fatalf("Failed to connect MySQL: %v", err)
	}
	log.Println("✓ MySQL connected")

	// 3. 初始化MongoDB
	mongoDB, err := initMongoDB(cfg.MongoDB)
	if err != nil {
		log.Fatalf("Failed to connect MongoDB: %v", err)
	}
	log.Println("✓ MongoDB connected")

	// 4. 初始化Redis
	redisClient, err := initRedis(cfg.Redis)
	if err != nil {
		log.Fatalf("Failed to connect Redis: %v", err)
	}
	log.Println("✓ Redis connected")

	// 5. 初始化缓存
	cacheService := cache.NewCache(redisClient)

	// 6. 初始化WebSocket Hub
	hub := ws.NewHub(mysqlDB)
	go hub.Run()
	log.Println("✓ WebSocket Hub started")

	// ========== 集群模式初始化 ==========
	// 通过环境变量 CLUSTER_ENABLED=true 或 config.yaml cluster.enabled=true 启用
	// 单机部署时不设置此变量，自动降级为原有单机模式，零影响
	clusterEnabled := os.Getenv("CLUSTER_ENABLED") == "true"
	if !clusterEnabled && cfg.Cluster != nil {
		clusterEnabled = cfg.Cluster.Enabled
	}
	if clusterEnabled {
		// 支持通过 config.yaml 或环境变量覆盖 nodeID
		if cfg.Cluster != nil && cfg.Cluster.NodeID != "" && os.Getenv("NODE_ID") == "" {
			os.Setenv("NODE_ID", cfg.Cluster.NodeID)
		}
		clusterBridge := ws.NewClusterBridge(redisClient, hub)
		hub.SetCluster(clusterBridge)

		// 后台启动 Redis 订阅监听（含自动断线重连）
		go clusterBridge.Start()

		log.Printf("✓ Cluster mode enabled, nodeID: %s", ws.NodeID)
	} else {
		log.Printf("✓ Single-node mode, nodeID: %s", ws.NodeID)
	}
	// ========== 集群模式初始化结束 ==========

	// 7. 初始化消息队列
	mqService := mq.NewMessageQueue(redisClient, cfg.MessageQueue.Workers)

	// 13. 初始化路由
	// 初始化搜索服务（ES未配置时自动降级为MongoDB正则搜索）
	var searchSvc *services.SearchService
	if cfg.Elasticsearch != nil && len(cfg.Elasticsearch.Addresses) > 0 {
		searchSvc = services.NewSearchService(
			cfg.Elasticsearch.Addresses,
			cfg.Elasticsearch.Username,
			cfg.Elasticsearch.Password,
			cfg.Elasticsearch.Index,
		)
	} else {
		searchSvc = services.NewSearchService(nil, "", "", "")
	}

	// 8. 初始化服务
	msgService := services.NewMessageService(mongoDB, mysqlDB, cacheService, mqService, hub, searchSvc)
	pushService := services.NewPushService(mysqlDB)
	// ★ 初始化可推送用户集合到Redis（有效push_token的用户ID）
	go func() {
		var deviceUserIDs []string
		mysqlDB.Table("user_devices").Where("push_token != ''").
			Distinct("CAST(user_id AS CHAR)").Pluck("CAST(user_id AS CHAR)", &deviceUserIDs)
		if len(deviceUserIDs) > 0 && cacheService != nil {
			_ = cacheService.LoadPushableUsers(context.Background(), deviceUserIDs)
			log.Printf("✓ Pushable users loaded: %d", len(deviceUserIDs))
		}
	}()
	services.RegisterMessageQueueHandlers(mqService, pushService, mysqlDB, cacheService)
	mqService.Start(mq.QueueMessageSend, mq.QueueMessageSync, mq.QueuePushNotify, mq.QueueUserChatSync)
	log.Println("✓ Message Queue started")

	// 9. 启动钱包定时任务（红包/转账过期退款）
	walletCron := services.NewWalletCronService(mysqlDB)
	walletCron.Start()
	defer walletCron.Stop()

	// 10. 启动外部媒体异步清理任务（账号注销后对象存储/CDN 资源）
	externalCleanupSvc := services.NewExternalCleanupService(
		mysqlDB,
		cfg.Server.ExternalCleanupHTTPDelete,
		cfg.Server.ExternalCleanupAllowedHosts,
	)
	externalCleanupSvc.Start()
	defer externalCleanupSvc.Stop()

	// 11. 设置Gin模式
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	// 12. 初始化 S3 存储（可选，nil 时自动降级本地存储）
	var s3Storage *storage.S3Storage
	if cfg.S3.Enabled {
		var s3Err error
		s3Storage, s3Err = storage.NewS3Storage(storage.S3Config{
			Region:          cfg.S3.Region,
			Bucket:          cfg.S3.Bucket,
			AccessKeyID:     cfg.S3.AccessKeyID,
			SecretAccessKey: cfg.S3.SecretAccessKey,
			CDNBaseURL:      cfg.S3.CDNBaseURL,
			Endpoint:        cfg.S3.Endpoint,
		})
		if s3Err != nil {
			log.Printf("⚠️  S3 初始化失败，降级本地存储: %v", s3Err)
			s3Storage = nil
		} else {
			log.Println("✓ S3 storage connected")
		}
	} else {
		log.Println("✓ S3 disabled，使用本地存储")
	}

	router := setupRouter(cfg, mysqlDB, mongoDB, cacheService, redisClient, hub, msgService, pushService, s3Storage, searchSvc)

	// 13. 启动服务器
	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      router,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
	}

	// 优雅关闭
	go func() {
		log.Printf("✓ Server starting on port %d", cfg.Server.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// 等待中断信号
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server shutdown error: %v", err)
	}

	mqService.Stop()
	log.Println("Server stopped")
}

// initMySQL 初始化MySQL连接
func initMySQL(cfg config.MySQLConfig, serverMode string) (*gorm.DB, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?charset=utf8mb4&parseTime=True&loc=Local",
		cfg.User, cfg.Password, cfg.Host, cfg.Port, cfg.Database)

	logLevel := logger.Info
	if serverMode == "release" {
		logLevel = logger.Warn
	}

	db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
	})
	if err != nil {
		return nil, err
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}

	sqlDB.SetMaxIdleConns(cfg.MaxIdleConns)
	sqlDB.SetMaxOpenConns(cfg.MaxOpenConns)
	sqlDB.SetConnMaxLifetime(cfg.ConnMaxLifetime)
	if cfg.ConnMaxIdleTime > 0 {
		sqlDB.SetConnMaxIdleTime(cfg.ConnMaxIdleTime) // ★ 空闲连接超时释放，防止连接池膨胀
	}

	// 自动迁移
	//
	// ⚠️ AutoMigrate 会在启动时对着 MySQL 跑 SHOW TABLES / ALTER 等 DDL，生产环境的问题：
	//   1. 慢：几十张表 x 每张 4~5 条 SQL，冷启动明显变慢；
	//   2. 危险：并发多节点滚动升级时，同一张表可能被多次 ALTER，MySQL 8 甚至会锁表；
	//   3. 不可控：Schema 变更应该走 DB Migration 工具（golang-migrate / gh-ost / flyway），
	//      让 DBA 提前评审，而不是应用启动时"自动"执行。
	//
	// 推荐生产做法：显式设 YIXIN_SKIP_AUTOMIGRATE=1，把 schema 交给独立的 migration 步骤。
	// 开发和首次部署仍可留空，保持"开箱即用"体验。
	if v := strings.ToLower(strings.TrimSpace(os.Getenv("YIXIN_SKIP_AUTOMIGRATE"))); v == "1" || v == "true" || v == "yes" {
		log.Println("[DB] YIXIN_SKIP_AUTOMIGRATE=1, 跳过 GORM AutoMigrate，schema 应由独立 migration 步骤维护")
		if err := migrateUserChatLastMsgID(db); err != nil {
			log.Printf("[Migration] migrate user_chats.last_msg_id failed: %v", err)
		}
		if err := ensureUserDeviceE2EEColumns(db); err != nil {
			log.Printf("[E2EE] ensure user_devices columns failed: %v", err)
		}
		if err := backfillHotUpdateDeliveryModes(db); err != nil {
			log.Printf("[HotUpdate] normalize delivery_mode failed: %v", err)
		}
		backfillUserShortIDs(db)
		initDefaultMembershipPlans(db)
		initDefaultApiTxtURL(db)
		fixChatMemberRoles(db)
		if err := initDefaultAdmin(db, serverMode); err != nil {
			return nil, err
		}
		initDefaultRoles(db)
		loadHeartbeatTimeout(db)
		return db, nil
	}

	if err := db.AutoMigrate(
		&models.User{},
		&models.UserDevice{},
		&models.PushDeliveryLog{},
		&models.UserRelation{},
		&models.Contact{},
		&models.Chat{},
		&models.ChatMember{},
		&models.UserChat{},
		&models.DiscoverItem{},
		&models.Admin{},
		&models.AdminLoginLog{},
		&models.Role{},
		&models.RoleMenu{},
		// 动态相关
		&models.Moment{},
		&models.MomentLike{},
		&models.MomentComment{},
		&models.Topic{},
		&models.BannedWord{},
		&models.MomentBlock{},
		&models.UserMomentBlock{},
		// 举报
		&models.Report{},
		// 加入请求
		&models.JoinRequest{},
		// 系统设置
		&models.SystemSetting{},
		&models.OfficialUser{},
		&models.OfficialGroup{},
		&models.OfficialChannel{},
		// 热更新补丁
		&models.HotUpdatePatch{},
		&models.HotUpdatePatchReport{},
		// 用户隐私和安全
		&models.UserPrivacySetting{},
		&models.UserEmojiStoreSetting{},
		&models.EmojiStorePackCatalog{},
		&models.UserBlock{},
		&models.UserSession{},
		&models.UserPushSetting{},
		&models.AccountDeletionAudit{},
		&models.AccountDeletionExternalTask{},
		// 音视频通话
		&models.Call{},
		&models.Meeting{},
		&models.MeetingParticipant{},
		&models.MeetingInvite{},
		// 钱包相关
		&models.Wallet{},
		&models.Transaction{},
		&models.RedPacket{},
		&models.RedPacketClaim{},
		&models.Transfer{},
		&models.WithdrawMethod{},
		&models.WithdrawRequest{},
		&models.RechargeMethod{},
		&models.RechargeOrder{},
		&models.ThirdPartyPaymentOrder{},
		// 会员相关
		&models.MembershipPlan{},
		&models.UserMembership{},
		&models.MembershipOrder{},
		// 群公告
		&models.ChatAnnouncement{},
		// 全局公告记录
		&models.SystemBroadcast{},
		// 启动弹窗公告
		&models.PopupAnnouncement{},
		// 邀请码
		&models.InviteCode{},
		&models.InviteCodeUsage{},
	); err != nil {
		return nil, err
	}
	if err := migrateUserChatLastMsgID(db); err != nil {
		log.Printf("[Migration] migrate user_chats.last_msg_id failed: %v", err)
	}
	if err := ensureUserDeviceE2EEColumns(db); err != nil {
		log.Printf("[E2EE] ensure user_devices columns failed: %v", err)
	}
	if err := backfillHotUpdateDeliveryModes(db); err != nil {
		log.Printf("[HotUpdate] normalize delivery_mode failed: %v", err)
	}

	// 为历史用户补齐平台短号（short_id）
	backfillUserShortIDs(db)

	// 初始化默认会员套餐
	initDefaultMembershipPlans(db)

	// 初始化 ServerDiscovery api.txt 地址（管理后台只读展示，缺行时插入默认值）
	initDefaultApiTxtURL(db)

	// 修复群组成员角色数据
	fixChatMemberRoles(db)

	// 初始化默认管理员
	if err := initDefaultAdmin(db, serverMode); err != nil {
		return nil, err
	}

	// 初始化内置角色（super_admin/admin/operator/demo_admin），缺行幂等插入
	initDefaultRoles(db)

	// 加载心跳超时设置
	loadHeartbeatTimeout(db)

	return db, nil
}

func migrateUserChatLastMsgID(db *gorm.DB) error {
	// GORM AutoMigrate 不会修改已有列类型
	// last_msg_id 从 bigint 改为 varchar(36)，需手动 ALTER
	type columnInfo struct {
		ColumnType string
	}
	var col columnInfo
	err := db.Raw(`
		SELECT DATA_TYPE as column_type
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE()
		  AND TABLE_NAME = 'user_chats'
		  AND COLUMN_NAME = 'last_msg_id'
	`).Scan(&col).Error
	if err != nil {
		return fmt.Errorf("query last_msg_id column type: %w", err)
	}
	// 如果已经是 varchar 就跳过
	if col.ColumnType == "varchar" {
		return nil
	}
	// 执行类型变更（bigint → varchar(36)），原有数字值清空为空字符串
	if err := db.Exec(`ALTER TABLE user_chats MODIFY COLUMN last_msg_id varchar(36) NOT NULL DEFAULT ''`).Error; err != nil {
		return fmt.Errorf("alter user_chats.last_msg_id: %w", err)
	}
	log.Printf("[Migration] user_chats.last_msg_id migrated bigint → varchar(36)")
	return nil
}

func ensureUserDeviceE2EEColumns(db *gorm.DB) error {
	migrator := db.Migrator()
	model := &models.UserDevice{}
	columns := []string{
		"E2EEPublicKey",
		"E2EEPublicKeyAlgo",
		"E2EEPublicKeyUpdatedAt",
	}
	for _, column := range columns {
		if migrator.HasColumn(model, column) {
			continue
		}
		if err := migrator.AddColumn(model, column); err != nil {
			return fmt.Errorf("add column %s: %w", column, err)
		}
		log.Printf("[E2EE] added missing user_devices column: %s", column)
	}
	legacyColumnsExist :=
		migrator.HasColumn(model, "e2_ee_public_key") &&
			migrator.HasColumn(model, "e2_ee_public_key_algo") &&
			migrator.HasColumn(model, "e2_ee_public_key_updated_at")
	if legacyColumnsExist {
		if err := db.Exec(`
			UPDATE user_devices
			SET
				e2ee_public_key = CASE
					WHEN (e2ee_public_key IS NULL OR e2ee_public_key = '') AND e2_ee_public_key IS NOT NULL AND e2_ee_public_key != ''
						THEN e2_ee_public_key
					ELSE e2ee_public_key
				END,
				e2ee_public_key_algo = CASE
					WHEN (e2ee_public_key_algo IS NULL OR e2ee_public_key_algo = '') AND e2_ee_public_key_algo IS NOT NULL AND e2_ee_public_key_algo != ''
						THEN e2_ee_public_key_algo
					ELSE e2ee_public_key_algo
				END,
				e2ee_public_key_updated_at = CASE
					WHEN e2ee_public_key_updated_at IS NULL AND e2_ee_public_key_updated_at IS NOT NULL
						THEN e2_ee_public_key_updated_at
					ELSE e2ee_public_key_updated_at
				END
		`).Error; err != nil {
			return fmt.Errorf("sync legacy e2ee columns: %w", err)
		}
		log.Printf("[E2EE] synced legacy user_devices E2EE columns into canonical columns")
	}
	return nil
}

func backfillHotUpdateDeliveryModes(db *gorm.DB) error {
	if err := db.Model(&models.HotUpdatePatch{}).
		Where("delivery_mode = '' OR delivery_mode IS NULL").
		Update("delivery_mode", models.HotUpdatePatchDeliveryModeSelfHosted).Error; err != nil {
		return fmt.Errorf("backfill hot_update_patches.delivery_mode: %w", err)
	}
	if err := db.Model(&models.HotUpdatePatchReport{}).
		Where("delivery_mode = '' OR delivery_mode IS NULL").
		Update("delivery_mode", models.HotUpdatePatchDeliveryModeSelfHosted).Error; err != nil {
		return fmt.Errorf("backfill hot_update_patch_reports.delivery_mode: %w", err)
	}
	return nil
}

// fixChatMemberRoles 修复群组成员角色数据
// 数据库角色定义: 0=普通成员, 1=管理员, 2=创建者
func fixChatMemberRoles(db *gorm.DB) {
	// 1. 修复群主角色：将群主的 role 设为 2
	result := db.Exec(`
		UPDATE chat_members cm
		INNER JOIN chats c ON cm.chat_id = c.id AND cm.user_id = c.owner_id
		SET cm.role = 2
		WHERE c.type IN (2, 3) AND cm.role != 2
	`)
	if result.Error != nil {
		log.Printf("修复群主角色失败: %v", result.Error)
	} else if result.RowsAffected > 0 {
		log.Printf("✓ 已修复 %d 个群主角色", result.RowsAffected)
	}

	// 2. 修复普通成员角色：将非群主且 role > 1 的成员设为 0
	// 注意：role = 1 的是管理员，保持不变
	result = db.Exec(`
		UPDATE chat_members cm
		INNER JOIN chats c ON cm.chat_id = c.id
		SET cm.role = 0
		WHERE c.type IN (2, 3)
		AND cm.user_id != c.owner_id
		AND cm.role > 1
	`)
	if result.Error != nil {
		log.Printf("修复成员角色失败: %v", result.Error)
	} else if result.RowsAffected > 0 {
		log.Printf("✓ 已修复 %d 个成员角色", result.RowsAffected)
	}
}

// backfillUserShortIDs 为历史数据补齐 short_id，保证"平台短号搜索"可用
func backfillUserShortIDs(db *gorm.DB) {
	const batchSize = 500
	for {
		var users []models.User
		if err := db.Where("short_id IS NULL").Limit(batchSize).Find(&users).Error; err != nil {
			log.Printf("补齐用户短号失败: %v", err)
			return
		}
		if len(users) == 0 {
			return
		}

		for _, u := range users {
			shortID := models.BuildUserShortID(u.ID)
			if err := db.Model(&models.User{}).
				Where("id = ? AND short_id IS NULL", u.ID).
				Update("short_id", shortID).Error; err != nil {
				log.Printf("补齐用户短号失败 user_id=%d err=%v", u.ID, err)
			}
		}

		if len(users) < batchSize {
			return
		}
	}
}

// initDefaultAdmin 初始化默认管理员
func initDefaultAdmin(db *gorm.DB, serverMode string) error {
	var count int64
	db.Model(&models.Admin{}).Count(&count)
	if count == 0 {
		username := strings.TrimSpace(os.Getenv("YIXIN_INITIAL_ADMIN_USERNAME"))
		password := strings.TrimSpace(os.Getenv("YIXIN_INITIAL_ADMIN_PASSWORD"))
		if username == "" {
			username = "admin"
		}
		if password == "" {
			if serverMode == "release" {
				return fmt.Errorf("YIXIN_INITIAL_ADMIN_PASSWORD must be set before creating the first admin in release mode")
			}
			password = "123456"
		}

		admin := models.Admin{
			Username: username,
			Nickname: "超级管理员",
			Email:    "admin@grimimim.com",
			Role:     "super_admin",
			Status:   1,
		}
		admin.SetPassword(password)
		if err := db.Create(&admin).Error; err != nil {
			return fmt.Errorf("create default admin: %w", err)
		} else {
			log.Printf("✓ Default admin created (username: %s). Please change the initial password immediately.", username)
		}
	}
	return nil
}

// initDefaultRoles 在启动时确保 roles 表里存在四个内置角色。
// 幂等：按 key 判断，已存在则跳过，不覆盖运维手动改过的 Name / Description / Code。
// 说明：这里只兜底"内置"角色；运维通过后台"角色管理"新建的自定义角色不会被这里覆盖。
func initDefaultRoles(db *gorm.DB) {
	now := time.Now()
	for _, seed := range models.BuiltInRoles {
		var count int64
		if err := db.Model(&models.Role{}).Where("`key` = ?", seed.Key).Count(&count).Error; err != nil {
			log.Printf("[Roles] check role %q failed: %v", seed.Key, err)
			continue
		}
		if count > 0 {
			continue
		}
		role := models.Role{
			Key:         seed.Key,
			Name:        seed.Name,
			Description: seed.Description,
			Code:        seed.Code,
			IsBuiltIn:   true,
			CreatedAt:   now,
			UpdatedAt:   now,
		}
		if err := db.Create(&role).Error; err != nil {
			log.Printf("[Roles] seed role %q failed: %v", seed.Key, err)
			continue
		}
		log.Printf("[Roles] seeded built-in role: %s (%s)", seed.Key, seed.Code)
	}
}

// loadHeartbeatTimeout 从数据库加载心跳超时设置
func loadHeartbeatTimeout(db *gorm.DB) {
	var setting models.SystemSetting
	if err := db.Where("`key` = ?", models.SettingHeartbeatTimeout).First(&setting).Error; err == nil {
		if seconds, err := strconv.Atoi(setting.Value); err == nil && seconds > 0 {
			ws.SetHeartbeatTimeout(seconds)
		}
	}
}

// initDefaultMembershipPlans 初始化默认会员套餐
func initDefaultMembershipPlans(db *gorm.DB) {
	var count int64
	db.Model(&models.MembershipPlan{}).Count(&count)
	if count > 0 {
		return
	}

	plans := []models.MembershipPlan{
		{
			Name:          "月度会员",
			Slug:          "monthly",
			DurationDays:  30,
			Price:         28,
			OriginalPrice: 38,
			BadgeLabel:    "PREMIUM",
			BadgeColor:    "#3390EC",
			Description:   "适合先体验高级功能的用户",
			Features:      `["会员徽章","更高上传限制","高级贴纸权限","更多会话置顶"]`,
			Status:        models.MembershipPlanStatusEnabled,
			Sort:          1,
		},
		{
			Name:          "季度会员",
			Slug:          "quarterly",
			DurationDays:  90,
			Price:         78,
			OriginalPrice: 114,
			BadgeLabel:    "PREMIUM",
			BadgeColor:    "#8B5CF6",
			Description:   "性价比更高，适合稳定使用",
			Features:      `["会员徽章","更高上传限制","高级贴纸权限","更多会话置顶"]`,
			Status:        models.MembershipPlanStatusEnabled,
			Sort:          2,
		},
		{
			Name:          "年度会员",
			Slug:          "yearly",
			DurationDays:  365,
			Price:         298,
			OriginalPrice: 456,
			BadgeLabel:    "PREMIUM",
			BadgeColor:    "#F59E0B",
			Description:   "最划算，适合长期使用",
			Features:      `["会员徽章","更高上传限制","高级贴纸权限","更多会话置顶"]`,
			Status:        models.MembershipPlanStatusEnabled,
			Sort:          3,
		},
	}
	for _, plan := range plans {
		plan.CreatedAt = time.Now()
		plan.UpdatedAt = time.Now()
		db.Create(&plan)
	}
	log.Println("✓ Default membership plans created")
}

// initDefaultApiTxtURL 首次启动时为 ServerDiscovery api.txt 地址插入默认行。
// 这个 setting 是「只读」性质：管理后台不允许 PUT/PATCH（isAllowedSystemSettingKey 白名单不放行），
// 需要修改就直接改数据库。这里在启动时兜底一次，避免 admin 页面首次显示空白。
// - 已存在（无论 value 是什么）→ 不覆盖，保持运维改过的值；
// - 不存在 → 用当前源码里的硬编码 fallback 作为默认值。
func initDefaultApiTxtURL(db *gorm.DB) {
	var count int64
	if err := db.Model(&models.SystemSetting{}).
		Where("`key` = ?", models.SettingApiTxtURL).
		Count(&count).Error; err != nil {
		log.Printf("[Init] count api_txt_url failed: %v", err)
		return
	}
	if count > 0 {
		return
	}
	now := time.Now()
	row := models.SystemSetting{
		Key:       models.SettingApiTxtURL,
		Value:     "https://admin.legg.click/api.txt",
		Type:      "string",
		Remark:    "客户端 ServerDiscovery 拉取节点列表用的 api.txt 地址。管理后台只读，改动直接改本行。",
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := db.Create(&row).Error; err != nil {
		log.Printf("[Init] insert default api_txt_url failed: %v", err)
		return
	}
	log.Println("✓ Default api_txt_url inserted into system_settings")
}

// initDefaultWithdrawMethods 初始化默认提现方式
func initDefaultWithdrawMethods(db *gorm.DB) {
	var count int64
	db.Model(&models.WithdrawMethod{}).Count(&count)
	if count == 0 {
		methods := []models.WithdrawMethod{
			{
				Name:      "支付宝",
				Icon:      "alipay",
				Fields:    `[{"key":"account","label":"支付宝账号","hint":"请输入手机号或邮箱","type":"text","required":true},{"key":"real_name","label":"真实姓名","hint":"请输入真实姓名","type":"text","required":true}]`,
				MinAmount: 10,
				MaxAmount: 50000,
				Fee:       0,
				Status:    1,
				Sort:      1,
			},
			{
				Name:      "微信",
				Icon:      "wechat",
				Fields:    `[{"key":"account","label":"微信号","hint":"请输入微信号","type":"text","required":true},{"key":"real_name","label":"真实姓名","hint":"请输入真实姓名","type":"text","required":true}]`,
				MinAmount: 10,
				MaxAmount: 50000,
				Fee:       0,
				Status:    1,
				Sort:      2,
			},
			{
				Name:      "银行卡",
				Icon:      "bank",
				Fields:    `[{"key":"bank_name","label":"银行名称","hint":"请输入开户银行","type":"text","required":true},{"key":"card_number","label":"银行卡号","hint":"请输入银行卡号","type":"bankCard","required":true},{"key":"real_name","label":"开户姓名","hint":"请输入持卡人姓名","type":"text","required":true}]`,
				MinAmount: 100,
				MaxAmount: 100000,
				Fee:       0.1,
				Status:    1,
				Sort:      3,
			},
		}
		for _, m := range methods {
			m.CreatedAt = time.Now()
			m.UpdatedAt = time.Now()
			db.Create(&m)
		}
		log.Println("✓ Default withdraw methods created")
	}
}

// initMongoDB 初始化MongoDB连接
func initMongoDB(cfg config.MongoDBConfig) (*mongo.Database, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	opts := options.Client().
		ApplyURI(cfg.URI).
		SetMaxPoolSize(cfg.MaxPoolSize).
		SetMinPoolSize(cfg.MinPoolSize)

	client, err := mongo.Connect(ctx, opts)
	if err != nil {
		return nil, err
	}

	if err := client.Ping(ctx, nil); err != nil {
		return nil, err
	}

	// ★ 为最近3个月+当前月的消息集合批量创建索引（幂等，已存在自动跳过）
	db := client.Database(cfg.Database)
	go func() {
		indexCtx, indexCancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer indexCancel()
		now := time.Now()
		for i := 0; i <= 3; i++ {
			t := now.AddDate(0, -i, 0)
			collName := "messages_" + t.Format("200601")
			coll := db.Collection(collName)
			indexes := []mongo.IndexModel{
				// 主查询：按会话倒序拉消息（最高频）
				{Keys: bson.D{{Key: "chat_id", Value: 1}, {Key: "seq", Value: -1}}},
				// 时间范围查询
				{Keys: bson.D{{Key: "chat_id", Value: 1}, {Key: "created_at", Value: -1}}},
				// 按发送者查询
				{Keys: bson.D{{Key: "sender_id", Value: 1}, {Key: "created_at", Value: -1}}},
				// 消息去重（FindMessageByClientID）
				{Keys: bson.D{{Key: "msg_id", Value: 1}},
					Options: options.Index().SetUnique(true).SetSparse(true)},
				// 按已删过滤
				{Keys: bson.D{{Key: "chat_id", Value: 1}, {Key: "deleted_for", Value: 1}}},
			}
			if _, err := coll.Indexes().CreateMany(indexCtx, indexes); err != nil {
				log.Printf("[MongoDB] 创建索引失败 collection=%s err=%v", collName, err)
			} else {
				log.Printf("[MongoDB] 索引确认完成 collection=%s", collName)
			}
		}
	}()

	return client.Database(cfg.Database), nil
}

// initRedis 初始化Redis连接（支持单机模式和 Sentinel 高可用模式）
func initRedis(cfg config.RedisConfig) (*redis.Client, error) {
	var client *redis.Client

	if cfg.Mode == "sentinel" {
		// Sentinel 模式：任意节点宕机自动切换主节点
		masterName := cfg.MasterName
		if masterName == "" {
			masterName = "mymaster"
		}
		if len(cfg.SentinelAddrs) == 0 {
			return nil, fmt.Errorf("sentinel mode requires sentinel_addrs")
		}
		log.Printf("[Redis] Sentinel 模式，master=%s，sentinels=%v", masterName, cfg.SentinelAddrs)
		client = redis.NewFailoverClient(&redis.FailoverOptions{
			MasterName:    masterName,
			SentinelAddrs: cfg.SentinelAddrs,
			Password:      cfg.Password,
			DB:            cfg.DB,
			PoolSize:      cfg.PoolSize,
			MinIdleConns:  cfg.MinIdleConns,
			DialTimeout:   3 * time.Second,
			ReadTimeout:   2 * time.Second,
			WriteTimeout:  2 * time.Second,
			// Sentinel 本身的连接选项
			SentinelPassword: cfg.Password,
		})
	} else {
		// 单机模式（默认）
		log.Printf("[Redis] 单机模式，addr=%s", cfg.Addr)
		client = redis.NewClient(&redis.Options{
			Addr:         cfg.Addr,
			Password:     cfg.Password,
			DB:           cfg.DB,
			PoolSize:     cfg.PoolSize,
			MinIdleConns: cfg.MinIdleConns,
			DialTimeout:  3 * time.Second,
			ReadTimeout:  2 * time.Second,
			WriteTimeout: 2 * time.Second,
		})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis ping failed: %w", err)
	}

	log.Printf("[Redis] 连接成功")
	return client, nil
}

// setupRouter 设置路由
func setupRouter(
	cfg *config.Config,
	db *gorm.DB,
	mongoDB *mongo.Database,
	cache *cache.Cache,
	redisClient *redis.Client,
	hub *ws.Hub,
	msgService *services.MessageService,
	pushService *services.PushService,
	s3Storage *storage.S3Storage,
	searchSvc *services.SearchService,
) *gin.Engine {
	router := gin.New()

	// ★ 信任代理白名单：只有来自这些 IP/CIDR 的 X-Forwarded-For 才会被 ClientIP() 采纳。
	// 未配置则 nil（Gin 不信任任何代理，只用 socket 直连地址），可防止外网伪造 header
	// 绕过 IP 限流。生产环境务必配置为 Nginx / K8s Ingress / CDN 的内网 IP 段。
	// 详见 config.server.trusted_proxies。
	if err := router.SetTrustedProxies(cfg.Server.TrustedProxies); err != nil {
		log.Printf("[WARN] SetTrustedProxies failed: %v (fallback to no trusted proxies)", err)
		_ = router.SetTrustedProxies(nil)
	}

	// ★ pprof 性能分析路由（仅内网可访问 —— InternalOnly 中间件强制校验源 IP）
	{
		pprofGroup := router.Group("/debug/pprof", middleware.InternalOnly())
		pprofGroup.GET("/", gin.WrapF(gopprof.Index))
		pprofGroup.GET("/cmdline", gin.WrapF(gopprof.Cmdline))
		pprofGroup.GET("/profile", gin.WrapF(gopprof.Profile))
		pprofGroup.GET("/symbol", gin.WrapF(gopprof.Symbol))
		pprofGroup.POST("/symbol", gin.WrapF(gopprof.Symbol))
		pprofGroup.GET("/trace", gin.WrapF(gopprof.Trace))
		pprofGroup.GET("/allocs", gin.WrapH(gopprof.Handler("allocs")))
		pprofGroup.GET("/block", gin.WrapH(gopprof.Handler("block")))
		pprofGroup.GET("/goroutine", gin.WrapH(gopprof.Handler("goroutine")))
		pprofGroup.GET("/heap", gin.WrapH(gopprof.Handler("heap")))
		pprofGroup.GET("/mutex", gin.WrapH(gopprof.Handler("mutex")))
		pprofGroup.GET("/threadcreate", gin.WrapH(gopprof.Handler("threadcreate")))
	}

	// 中间件
	router.Use(gin.Recovery())
	router.Use(middleware.Logger())
	// CORS 严格白名单：
	// - config.server.allowed_origins 优先（推荐配置）
	// - 未配置时回退到 BaseURL / RegisterBaseURL（保证旧配置也能跑）
	// - 都为空则允许所有来源（开发模式，且不带 credentials）
	corsOrigins := append([]string(nil), cfg.Server.AllowedOrigins...)
	if len(corsOrigins) == 0 {
		if cfg.Server.BaseURL != "" {
			corsOrigins = append(corsOrigins, cfg.Server.BaseURL)
		}
		if cfg.Server.RegisterBaseURL != "" && cfg.Server.RegisterBaseURL != cfg.Server.BaseURL {
			corsOrigins = append(corsOrigins, cfg.Server.RegisterBaseURL)
		}
	}
	router.Use(middleware.CORS(corsOrigins...))

	// 全局拦截 OPTIONS 预检请求，直接返回 204
	// 必须在所有路由注册之前，确保 Cloudflare/CDN 转发的预检能得到正确响应
	router.OPTIONS("/*path", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	router.Use(middleware.RateLimit(cache))

	// ★ Prometheus 监控端点 — 仅允许内网 IP 访问
	router.GET("/metrics", middleware.InternalOnly(), gin.WrapH(promhttp.Handler()))

	// ★ HTTP 请求指标中间件
	router.Use(func(c *gin.Context) {
		if c.FullPath() == "/metrics" {
			c.Next()
			return
		}
		start := time.Now()
		c.Next()
		duration := time.Since(start).Seconds()
		status := strconv.Itoa(c.Writer.Status())
		metrics.HTTPRequestTotal.WithLabelValues(c.Request.Method, c.FullPath(), status).Inc()
		metrics.HTTPRequestDuration.WithLabelValues(c.Request.Method, c.FullPath()).Observe(duration)
	})

	baseURL := strings.TrimSpace(cfg.Server.BaseURL)
	if baseURL == "" {
		scheme := "http"
		if cfg.Server.Port == 443 {
			scheme = "https"
		}
		baseURL = fmt.Sprintf("%s://localhost:%d", scheme, cfg.Server.Port)
	}
	baseURL = strings.TrimRight(baseURL, "/")

	// 静态文件服务 - 用于访问上传的文件
	uploadDir := cfg.Server.UploadDir
	if uploadDir == "" {
		uploadDir = "./uploads"
	}
	uploads := router.Group("/uploads")
	uploads.Use(middleware.MediaCORS(baseURL))
	// ★ 静态目录安全头：nosniff + CSP + /uploads/files/ 强制 attachment，
	// 防止用户上传的文件被浏览器嗅探成 HTML/JS 执行。
	uploads.Use(middleware.MediaSecurityHeaders())
	uploads.StaticFS("/", gin.Dir(uploadDir, false))

	// 根路径：访问 / 时提示后端已启动
	router.GET("/", func(c *gin.Context) {
		c.String(200, "壹信IM后端启动成功")
	})
	router.GET("/favicon.ico", func(c *gin.Context) { c.Status(204) })
	router.GET("/robots.txt", func(c *gin.Context) {
		c.Data(200, "text/plain; charset=utf-8", []byte("User-agent: *\nDisallow: /\n"))
	})

	// ★ 健康检查（新增 node_id 字段，集群运维时可区分节点）
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":  "ok",
			"time":    time.Now().Unix(),
			"node_id": ws.NodeID,
		})
	})

	// ★ WebSocket 状态（新增 node_id 和集群开关状态）
	// 仅内网可访问 —— 该端点会暴露在线用户数、集群拓扑等敏感运维信息，
	// 生产环境绝对不能公网直连，必须走 Nginx / VPN 内网。
	router.GET("/ws/stats", middleware.InternalOnly(), func(c *gin.Context) {
		stats := hub.GetStats()
		// ★ stats 直接是 map[string]interface{}，追加集群信息后返回
		stats["node_id"] = ws.NodeID
		stats["cluster_enabled"] = hub.ClusterEnabled()
		c.JSON(200, stats)
	})

	// API路由
	api := router.Group("/api/v1")
	{
		onlinePaySvc := services.NewOnlinePaymentService(cfg, db)
		onlinePayHandler := handlers.NewOnlinePaymentHandler(onlinePaySvc, db)
		smsSvc := services.NewSMSService(cfg, db)

		// 微信/支付宝异步通知（无 JWT）
		api.POST("/payment/notify/wechat", onlinePayHandler.WeChatNotify)
		api.POST("/payment/notify/alipay", onlinePayHandler.AlipayNotify)

		// Ping - 用于触发网络权限弹窗和连通性测试
		api.GET("/ping", func(c *gin.Context) {
			c.JSON(200, gin.H{
				"status":  "pong",
				"time":    time.Now().Unix(),
				"version": "1.0.0",
			})
		})

		// 认证路由（无需登录）
		auth := api.Group("/auth")
		{
			// 验证码 Store 用 Redis 实现，保证集群里任意节点都能校验彼此发出的验证码。
			// TTL 与短信验证码保持一致（5 分钟），到期自动淘汰。
			captchaStore := captchastore.New(redisClient, "captcha:", 5*time.Minute)
			authHandler := handlers.NewAuthHandler(db, cache, msgService, smsSvc, captchaStore)
			qrLoginHandler := handlers.NewQRLoginHandler(db, cache)
			auth.POST("/login", authHandler.Login)
			auth.POST("/register", authHandler.Register)
			auth.POST("/captcha", authHandler.GetCaptcha)
			auth.POST("/check-username", authHandler.CheckUsername)
			auth.POST("/password/send-reset-code", authHandler.SendPasswordResetCode)
			auth.POST("/password/reset-by-code", authHandler.ResetPasswordByCode)
			auth.POST("/device-lock/verify", authHandler.VerifyDeviceLockLogin)
			auth.POST("/qr-login/create", qrLoginHandler.Create)
			auth.GET("/qr-login/status/:ticket", qrLoginHandler.GetStatus)
			auth.POST("/qr-login/confirm/:ticket", middleware.Auth(cache), middleware.RequirePhoneBind(db, cache), qrLoginHandler.Confirm)
			auth.POST("/refresh", authHandler.RefreshToken)
			auth.POST("/logout", middleware.Auth(cache), authHandler.Logout)
			auth.POST("/change-password", middleware.Auth(cache), middleware.RequirePhoneBind(db, cache), authHandler.ChangePassword)
		}

		// 需要认证的路由
		authorized := api.Group("")
		authorized.Use(middleware.Auth(cache), middleware.RequirePhoneBind(db, cache))
		{
			// 用户
			user := authorized.Group("/user")
			{
				userHandler := handlers.NewUserHandler(db, cache, hub, smsSvc, mongoDB, uploadDir)
				user.GET("/me", userHandler.GetMe)
				user.PUT("/me", userHandler.UpdateMe)
				user.PUT("/e2ee/device-key", userHandler.UpdateCurrentDeviceE2EEKey)
				user.POST("/check-username", userHandler.CheckUsername)
				user.POST("/phone/send-bind-code", middleware.WalletRateLimit(cache, 5, time.Minute), userHandler.SendPhoneBindCode)
				user.POST("/phone/bind", userHandler.BindPhone)
				user.POST("/password/send-change-code", middleware.WalletRateLimit(cache, 5, time.Minute), userHandler.SendPasswordChangeCode)
				user.POST("/password/change-by-code", userHandler.ChangePasswordByCode)
				user.POST("/account/send-delete-code", middleware.WalletRateLimit(cache, 5, time.Minute), userHandler.SendDeleteAccountCode)
				user.GET("/search", userHandler.SearchUsers)
				user.GET("/search-all", userHandler.SearchAll)
				user.GET("/privacy", userHandler.GetPrivacySettings)
				user.PUT("/privacy", userHandler.UpdatePrivacySettings)
				user.POST("/two-step", userHandler.UpdateTwoStep)
				user.GET("/emoji-store/catalog", userHandler.GetEmojiStoreCatalog)
				user.GET("/emoji-store", userHandler.GetEmojiStore)
				user.PUT("/emoji-store", userHandler.UpdateEmojiStore)
				user.GET("/blocked", userHandler.GetBlockedUsers)
				user.GET("/blocked/check", userHandler.CheckBlockStatus)
				user.POST("/blocked", userHandler.BlockUser)
				user.DELETE("/blocked/:blocked_id", userHandler.UnblockUser)
				user.GET("/sessions", userHandler.GetSessions)
				user.POST("/sessions/terminate-others", userHandler.TerminateOtherSessions)
				user.DELETE("/sessions/:session_id", userHandler.TerminateSession)
				user.GET("/devices", userHandler.GetDevices)
				user.DELETE("/devices/:device_id", userHandler.TerminateDevice)
				user.POST("/devices/terminate-others", userHandler.TerminateOtherDevices)
				user.POST("/push-token", userHandler.UpdatePushToken)
				user.DELETE("/push-token", userHandler.DeletePushToken)
				user.PUT("/push-settings", userHandler.UpdatePushSettings)
				user.GET("/push-settings", userHandler.GetPushSettings)
				user.DELETE("/account", userHandler.DeleteAccount)
				user.GET("/:id", userHandler.GetUser)
				user.GET("/:id/common-groups", userHandler.GetCommonGroups)
			}

			// 会话
			chat := authorized.Group("/chat")
			{
				chatHandler := handlers.NewChatHandler(db, cache, hub, msgService, searchSvc)
				chat.GET("/list", chatHandler.GetChatList)
				chat.POST("/create", chatHandler.CreateChat)
				chat.GET("/:id", chatHandler.GetChat)
				chat.PUT("/:id", chatHandler.UpdateChat)
				chat.DELETE("/:id", chatHandler.DeleteChat)
				chat.GET("/:id/members", chatHandler.GetMembers)
				chat.GET("/:id/members/search", chatHandler.SearchMembers)
				chat.POST("/:id/members", chatHandler.AddMembers)
				chat.DELETE("/:id/members/:user_id", chatHandler.RemoveMember)
				chat.PUT("/:id/members/:user_id/role", chatHandler.SetMemberRole)
				chat.POST("/:id/leave", chatHandler.LeaveChat)
				chat.POST("/:id/hide", chatHandler.HideChat)
				chat.POST("/invite/:invite_link/join", chatHandler.JoinChatByInviteLink)
				chat.POST("/:id/join", chatHandler.JoinChat)
				chat.GET("/:id/join-requests", chatHandler.GetJoinRequests)
				chat.POST("/:id/join-requests/:request_id/review", chatHandler.ReviewJoinRequest)
				chat.POST("/:id/mute", chatHandler.MuteMember)
				chat.POST("/:id/unmute", chatHandler.UnmuteMember)
				chat.GET("/:id/mute-status", chatHandler.GetMemberMuteStatus)
				chat.POST("/:id/pin", chatHandler.TogglePin)
				chat.POST("/:id/mute-chat", chatHandler.ToggleMuteChat)
				chat.POST("/:id/toggle-unread", chatHandler.ToggleUnread)
				pinHandler := handlers.NewPinHandler(db, mongoDB, hub)
				chat.POST("/:id/pin-message", pinHandler.PinMessage)
				chat.DELETE("/:id/pin-message", pinHandler.UnpinMessage)
				chat.GET("/:id/pin-message", pinHandler.GetPinnedMessage)
				announcementHandler := handlers.NewAnnouncementHandler(db, hub)
				chat.GET("/:id/announcements", announcementHandler.GetAnnouncements)
				chat.POST("/:id/announcements", announcementHandler.CreateAnnouncement)
				chat.PUT("/:id/announcements/:announcement_id", announcementHandler.UpdateAnnouncement)
				chat.DELETE("/:id/announcements/:announcement_id", announcementHandler.DeleteAnnouncement)
				chat.POST("/:id/clear", chatHandler.ClearChatHistory)
				chat.POST("/:id/clear-both", chatHandler.ClearChatHistoryForBoth)
				chat.GET("/:id/search", chatHandler.SearchMessages)
			}

			// 消息
			message := authorized.Group("/message")
			{
				msgHandler := handlers.NewMessageHandler(db, msgService, pushService, hub, cache)
				message.GET("/e2ee/device-keys", msgHandler.GetChatDeviceKeys)
				// 消息发送单用户限流：每 5 秒 60 条（≈ 12/秒峰值，正常聊天绰绰有余，能挡住
				// 脚本刷屏 / 撞消息）。原值 10000/秒 相当于没设，一个账号就能把 MongoDB 打挂。
				message.POST("/send", middleware.UserRateLimit(cache, 60, 5*time.Second), msgHandler.SendMessage)
				message.GET("/list", msgHandler.GetMessages)
				message.POST("/revoke", msgHandler.RevokeMessage)
				message.POST("/delete", msgHandler.DeleteMessage)
				message.POST("/sync", msgHandler.SyncMessages)
				message.POST("/read", msgHandler.MarkAsRead)
				message.POST("/reaction/add", msgHandler.AddReaction)
				message.POST("/reaction/remove", msgHandler.RemoveReaction)
				message.POST("/forward", msgHandler.ForwardMessage)
				message.POST("/edit", msgHandler.EditMessage)
				message.GET("/media", msgHandler.GetChatMedia)
				message.GET("/media/count", msgHandler.GetChatMediaCount)
			}

			// 联系人
			contact := authorized.Group("/contact")
			{
				contactHandler := handlers.NewContactHandler(db, cache, hub, msgService)
				contact.GET("/list", contactHandler.GetContacts)
				contact.POST("/add", contactHandler.AddContact)
				contact.DELETE("/:id", contactHandler.DeleteContact)
				contact.PUT("/:id/remark", contactHandler.UpdateRemark)
				contact.GET("/requests", contactHandler.GetFriendRequests)
				contact.POST("/requests/:id/accept", contactHandler.AcceptFriendRequest)
				contact.POST("/requests/:id/reject", contactHandler.RejectFriendRequest)
			}

			// 签到
			checkin := authorized.Group("/checkin")
			{
				checkinHandler := handlers.NewCheckinHandler(db)
				checkin.POST("", checkinHandler.DoCheckin)
				checkin.GET("/calendar", checkinHandler.GetCalendar)
			}

			popupAnn := authorized.Group("/popup-announcement")
			{
				popupAnnHandler := handlers.NewPopupAnnouncementHandler(db)
				popupAnn.GET("/active", popupAnnHandler.GetActivePopupAnnouncement)
			}

			// 举报
			reportHandler := handlers.NewReportHandler(db)
			authorized.POST("/report", reportHandler.CreateReport)

			// 链接预览
			linkPreviewHandler := handlers.NewLinkPreviewHandler()
			authorized.GET("/link-preview", linkPreviewHandler.GetPreview)

			// 动态广场
			moment := authorized.Group("/moment")
			{
				momentHandler := handlers.NewMomentHandler(db, hub)
				moment.GET("/list", momentHandler.GetMomentList)
				moment.GET("/:id", momentHandler.GetMoment)
				moment.GET("/:id/detail", momentHandler.GetMoment)
				moment.POST("/publish", momentHandler.PublishMoment)
				moment.PUT("/:id", momentHandler.UpdateMoment)
				moment.DELETE("/:id", momentHandler.DeleteMoment)
				moment.POST("/:id/like", momentHandler.LikeMoment)
				moment.POST("/:id/unlike", momentHandler.UnlikeMoment)
				moment.GET("/:id/comments", momentHandler.GetComments)
				moment.POST("/:id/comment", momentHandler.AddComment)
				moment.GET("/topics/hot", momentHandler.GetHotTopics)
				moment.GET("/my/moments", momentHandler.GetMyMoments)
				moment.GET("/my/likes", momentHandler.GetMyLikes)
				moment.GET("/my/comments", momentHandler.GetMyComments)
				moment.GET("/my/received-likes", momentHandler.GetReceivedLikes)
				moment.GET("/search", momentHandler.SearchMoments)
				moment.POST("/:id/block", momentHandler.BlockMoment)
				moment.POST("/block-user/:userId", momentHandler.BlockUser)
			}

			// 音视频通话（声网）
			call := authorized.Group("/call")
			{
				agoraService := services.NewAgoraService(
					cfg.Agora.Enabled,
					cfg.Agora.AppID,
					cfg.Agora.AppCertificate,
					cfg.Agora.TokenExpire,
				)
				callHandler := handlers.NewCallHandler(db, agoraService, hub, msgService, pushService)
				call.GET("/config", callHandler.GetAgoraConfig)
				call.GET("/token", callHandler.GetToken)
				call.POST("/create", callHandler.CreateCall)
				call.POST("/accept", callHandler.AcceptCall)
				call.POST("/reject", callHandler.RejectCall)
				call.POST("/end", callHandler.EndCall)
				call.DELETE("/:call_id", callHandler.CancelCall)
				call.GET("/history", callHandler.GetCallHistory)
				// GetPendingCall: 客户端在 WS 重连 / 页面恢复可见时轮询，
				// 用来补偿"WS 掉线时错过 incoming_call"这种 web 上高发的场景。
				call.GET("/pending", callHandler.GetPendingCall)
			}

			// 群会议（声网）
			meeting := authorized.Group("/meeting")
			{
				agoraService := services.NewAgoraService(
					cfg.Agora.Enabled,
					cfg.Agora.AppID,
					cfg.Agora.AppCertificate,
					cfg.Agora.TokenExpire,
				)
				meetingHandler := handlers.NewMeetingHandler(db, agoraService, hub, pushService, msgService)
				meeting.POST("/create", meetingHandler.CreateMeeting)
				meeting.POST("/join", meetingHandler.JoinMeeting)
				meeting.POST("/join-request/review", meetingHandler.ReviewJoinRequest)
				meeting.POST("/title", meetingHandler.UpdateMeetingTitle)
				meeting.POST("/leave", meetingHandler.LeaveMeeting)
				meeting.POST("/invite", meetingHandler.InviteMembers)
				meeting.POST("/end", meetingHandler.EndMeeting)
				meeting.POST("/member/mute", meetingHandler.MuteMember)
				meeting.POST("/member/kick", meetingHandler.KickMember)
				meeting.POST("/host/transfer", meetingHandler.TransferHost)
				meeting.GET("/token", meetingHandler.GetToken)
				meeting.GET("/detail", meetingHandler.GetMeetingDetail)
				meeting.GET("/active", meetingHandler.GetActiveMeeting)
			}

			// 文件上传
			upload := authorized.Group("/upload")
			{
				baseURL := cfg.Server.BaseURL
				if baseURL == "" {
					baseURL = fmt.Sprintf("http://localhost:%d", cfg.Server.Port)
				}
				uploadHandler := handlers.NewUploadHandler(db, uploadDir, baseURL, s3Storage)
				upload.POST("/image", uploadHandler.UploadImage)
				upload.POST("/images", uploadHandler.UploadMultipleImages)
				upload.POST("/video", uploadHandler.UploadVideo)
				upload.POST("/avatar", uploadHandler.UploadAvatar)
				upload.POST("/voice", uploadHandler.UploadVoice)
				upload.POST("/file", uploadHandler.UploadFile)
			}

			// 钱包
			wallet := authorized.Group("/wallet")
			{
				walletHandler := handlers.NewWalletHandler(db, hub, msgService)
				membershipHandler := handlers.NewMembershipHandler(db)
				wrl5 := middleware.WalletRateLimit(cache, 5, time.Minute)
				wrl10 := middleware.WalletRateLimit(cache, 10, time.Minute)
				wallet.GET("/online-pay/options", onlinePayHandler.Options)
				wallet.POST("/online-pay/create", wrl5, onlinePayHandler.Create)
				wallet.GET("/online-pay/order/:out_trade_no", onlinePayHandler.QueryOrder)
				wallet.GET("", walletHandler.GetWallet)
				wallet.GET("/membership", membershipHandler.GetMyMembership)
				wallet.GET("/membership/plans", membershipHandler.ListPlans)
				wallet.POST("/membership/purchase", wrl5, membershipHandler.Purchase)
				wallet.GET("/settings", walletHandler.GetWalletSettings)
				wallet.GET("/recharge-methods", walletHandler.GetRechargeMethods)
				wallet.POST("/recharge-order", wrl5, walletHandler.CreateRechargeOrder)
				wallet.GET("/recharge-orders", walletHandler.GetRechargeOrders)
				wallet.POST("/pay-password", walletHandler.SetPayPassword)
				wallet.POST("/verify-password", walletHandler.VerifyPayPassword)
				wallet.GET("/transactions", walletHandler.GetTransactions)
				// ⚠️ 严禁开启 /wallet/recharge —— 该 handler 只做鉴权就直接给用户余额 +amount，
				// 等价于"白送钱后门"。真实充值必须走 /wallet/online-pay/create + 微信/支付宝
				// 服务端异步回调 /payment/notify/*（订单号+签名校验+幂等落账）。
				// wallet.POST("/recharge", wrl5, walletHandler.Recharge)
				wallet.POST("/red-packet/send", wrl5, walletHandler.SendRedPacket)
				wallet.POST("/red-packet/:id/claim", wrl10, walletHandler.ClaimRedPacket)
				wallet.GET("/red-packet/:id", walletHandler.GetRedPacket)
				wallet.POST("/transfer/send", wrl5, walletHandler.SendTransfer)
				wallet.POST("/transfer/:id/accept", wrl5, walletHandler.AcceptTransfer)
				wallet.POST("/transfer/:id/reject", wrl5, walletHandler.RejectTransfer)
				wallet.GET("/transfer/:id", walletHandler.GetTransfer)
				wallet.GET("/withdraw/methods", walletHandler.GetWithdrawMethods)
				wallet.POST("/withdraw", wrl5, walletHandler.CreateWithdrawRequest)
			}
		}

		// WebSocket连接
		api.GET("/ws", middleware.Auth(cache) /* , middleware.RequirePhoneBind(db, cache) */, handlers.HandleWebSocket(hub, cfg.WebSocket, db, corsOrigins...))

		// ========== 官方客服独立后台 API ==========
		serviceAdminHandler := handlers.NewServiceAdminHandler(db, cache, smsSvc)
		serviceAdminAPI := api.Group("/service-admin")
		{
			serviceAdminAPI.POST("/auth/login", serviceAdminHandler.Login)

			serviceAdminAuth := serviceAdminAPI.Group("")
			serviceAdminAuth.Use(middleware.Auth(cache))
			{
				serviceAdminAuth.POST("/auth/logout", serviceAdminHandler.Logout)
				serviceAdminAuth.PUT("/password", serviceAdminHandler.UpdatePassword)
				serviceAdminAuth.POST("/phone/send-bind-code", serviceAdminHandler.SendPhoneBindCode)
				serviceAdminAuth.POST("/phone/bind", serviceAdminHandler.BindPhone)
				serviceAdminAuth.GET("/profile", serviceAdminHandler.GetProfile)
				serviceAdminAuth.GET("/dashboard", serviceAdminHandler.GetDashboard)
				serviceAdminAuth.GET("/invite-code", serviceAdminHandler.GetInviteCode)
				serviceAdminAuth.GET("/invitees", serviceAdminHandler.GetInvitees)
				serviceAdminAuth.GET("/welcome-message", serviceAdminHandler.GetWelcomeMessage)
				serviceAdminAuth.PATCH("/welcome-message", serviceAdminHandler.UpdateWelcomeMessage)
			}
		}

		// ========== 管理后台 API ==========
		adminAPI := api.Group("/admin")
		{
			adminHandler := handlers.NewAdminHandler(db, cache)

			adminAPI.POST("/login", adminHandler.Login)

			adminAuth := adminAPI.Group("")
			adminAuth.Use(middleware.AdminAuth(db))
			{
				adminAuth.GET("/me", adminHandler.GetCurrentAdmin)
				adminAuth.PUT("/password", adminHandler.UpdatePassword)

				adminAuth.GET("/list", middleware.RequireRole("super_admin"), adminHandler.ListAdmins)
				adminAuth.POST("/create", middleware.RequireRole("super_admin"), adminHandler.CreateAdmin)
				adminAuth.PUT("/:id", middleware.RequireRole("super_admin"), adminHandler.UpdateAdmin)
				adminAuth.DELETE("/:id", middleware.RequireRole("super_admin"), adminHandler.DeleteAdmin)

				// 角色-菜单权限（前端 "角色权限" 页面；仅 super_admin 可读写）
				roleMenuHandler := handlers.NewRoleMenuHandler(db)
				adminAuth.GET("/role-menus", middleware.RequireRole("super_admin"), roleMenuHandler.ListRoleMenus)
				adminAuth.PUT("/role-menus/:role", middleware.RequireRole("super_admin"), roleMenuHandler.UpdateRoleMenu)

				// 角色管理（前端 "角色管理" 页面；仅 super_admin 可读写）
				roleHandler := handlers.NewRoleHandler(db)
				adminAuth.GET("/roles", middleware.RequireRole("super_admin"), roleHandler.ListRoles)
				adminAuth.POST("/roles", middleware.RequireRole("super_admin"), roleHandler.CreateRole)
				adminAuth.PUT("/roles/:id", middleware.RequireRole("super_admin"), roleHandler.UpdateRole)
				adminAuth.DELETE("/roles/:id", middleware.RequireRole("super_admin"), roleHandler.DeleteRole)
				adminAuth.GET("/roles/:key/admins", middleware.RequireRole("super_admin"), roleHandler.GetRoleAdmins)

				userMgmt := adminAuth.Group("/users")
				{
					userMgmtHandler := handlers.NewUserMgmtHandler(db, hub, cache, pushService)
					userMgmt.GET("/list", userMgmtHandler.ListUsers)
					userMgmt.GET("/stats", userMgmtHandler.GetUserStats)
					userMgmt.GET("/:id/diagnostics", userMgmtHandler.GetUserDiagnostics)
					userMgmt.PUT("/:id", middleware.RequireWriteRole(), userMgmtHandler.UpdateUser)
					userMgmt.PUT("/:id/status", middleware.RequireWriteRole(), userMgmtHandler.UpdateUserStatus)
					userMgmt.POST("/:id/kick", middleware.RequireWriteRole(), userMgmtHandler.KickUser)
					userMgmt.POST("/:id/ban", middleware.RequireWriteRole(), userMgmtHandler.BanUser)
					userMgmt.POST("/:id/unban", middleware.RequireWriteRole(), userMgmtHandler.UnbanUser)
					userMgmt.POST("/:id/freeze", middleware.RequireWriteRole(), userMgmtHandler.FreezeUser)
					userMgmt.POST("/:id/unfreeze", middleware.RequireWriteRole(), userMgmtHandler.UnfreezeUser)
					userMgmt.POST("/:id/reset-password", middleware.RequireWriteRole(), userMgmtHandler.ResetUserPassword)
					userMgmt.POST("/:id/test-push", middleware.RequireWriteRole(), userMgmtHandler.SendTestPush)
					userMgmt.PUT("/:id/membership", userMgmtHandler.SetMembership)
				}

				chatMgmt := adminAuth.Group("/chats")
				{
					chatMgmtHandler := handlers.NewChatMgmtHandler(db, hub)
					chatMgmt.GET("/list", chatMgmtHandler.ListChats)
					chatMgmt.GET("/groups", chatMgmtHandler.ListGroups)
					chatMgmt.GET("/channels", chatMgmtHandler.ListChannels)
					chatMgmt.GET("/stats", chatMgmtHandler.GetChatStats)
					chatMgmt.GET("/:id", chatMgmtHandler.GetChatDetail)
					chatMgmt.GET("/:id/members", chatMgmtHandler.GetChatMembers)
					chatMgmt.PUT("/:id/status", middleware.RequireWriteRole(), chatMgmtHandler.UpdateChatStatus)
					chatMgmt.POST("/:id/ban", middleware.RequireWriteRole(), chatMgmtHandler.BanChat)
					chatMgmt.POST("/:id/unban", middleware.RequireWriteRole(), chatMgmtHandler.UnbanChat)
					chatMgmt.POST("/:id/dissolve", middleware.RequireWriteRole(), chatMgmtHandler.DissolveChat)
					chatMgmt.DELETE("/:id", middleware.RequireWriteRole(), chatMgmtHandler.DeleteChat)
					chatMgmt.DELETE("/:id/members/:member_id", middleware.RequireWriteRole(), chatMgmtHandler.RemoveChatMember)
					// 群组「水军」数量：仅面向 type=2 的群聊，用于把客户端看到的成员/在线数虚增
					chatMgmt.PUT("/:id/fake-members", middleware.RequireWriteRole(), chatMgmtHandler.UpdateFakeMemberCount)
				}

				stats := adminAuth.Group("/stats")
				{
					statsHandler := handlers.NewStatsHandler(db, mongoDB, cache)
					stats.GET("/dashboard", statsHandler.GetDashboardStats)
					stats.GET("/runtime", statsHandler.GetRuntimeStatus)
					stats.GET("/users", statsHandler.GetUserStats)
					stats.GET("/messages", statsHandler.GetMessageStats)
				}

				momentMgmt := adminAuth.Group("/moments")
				{
					momentMgmtHandler := handlers.NewMomentMgmtHandler(db)
					momentMgmt.GET("/list", momentMgmtHandler.ListMoments)
					momentMgmt.GET("/stats", momentMgmtHandler.GetMomentStats)
					momentMgmt.PUT("/:id/status", middleware.RequireWriteRole(), momentMgmtHandler.UpdateMomentStatus)
					momentMgmt.DELETE("/:id", middleware.RequireWriteRole(), momentMgmtHandler.DeleteMoment)
				}

				topicMgmt := adminAuth.Group("/topics")
				{
					momentMgmtHandler := handlers.NewMomentMgmtHandler(db)
					topicMgmt.GET("/list", momentMgmtHandler.ListTopics)
					topicMgmt.POST("/create", middleware.RequireWriteRole(), momentMgmtHandler.CreateTopic)
					topicMgmt.PUT("/:id", middleware.RequireWriteRole(), momentMgmtHandler.UpdateTopic)
					topicMgmt.DELETE("/:id", middleware.RequireWriteRole(), momentMgmtHandler.DeleteTopic)
				}

				bannedMgmt := adminAuth.Group("/banned-words")
				{
					momentMgmtHandler := handlers.NewMomentMgmtHandler(db)
					bannedMgmt.GET("/list", momentMgmtHandler.ListBannedWords)
					bannedMgmt.POST("/create", middleware.RequireWriteRole(), momentMgmtHandler.CreateBannedWord)
					bannedMgmt.POST("/batch", middleware.RequireWriteRole(), momentMgmtHandler.BatchCreateBannedWords)
					bannedMgmt.PUT("/:id", middleware.RequireWriteRole(), momentMgmtHandler.UpdateBannedWord)
					bannedMgmt.DELETE("/:id", middleware.RequireWriteRole(), momentMgmtHandler.DeleteBannedWord)
				}

				reportMgmt := adminAuth.Group("/reports")
				{
					reportHandler := handlers.NewReportHandler(db)
					reportMgmt.GET("/list", reportHandler.ListReports)
					reportMgmt.GET("/stats", reportHandler.GetReportStats)
					reportMgmt.POST("/:id/process", middleware.RequireWriteRole(), reportHandler.ProcessReport)
					reportMgmt.DELETE("/:id", middleware.RequireWriteRole(), reportHandler.DeleteReport)
				}

				checkinMgmt := adminAuth.Group("/checkins")
				{
					checkinHandler := handlers.NewCheckinHandler(db)
					checkinMgmt.GET("/list", checkinHandler.AdminListCheckins)
				}

				settingMgmt := adminAuth.Group("/settings")
				{
					settingHandler := handlers.NewSettingHandler(db, pushService)
					settingHandler.SetSMSService(smsSvc)
					settingHandler.SetCache(cache) // ★ 注入缓存，系统设置变更时主动失效
					smsSettingsHandler := handlers.NewSmsSettingsHandler(db, cfg, smsSvc)
					discoverHandler := handlers.NewDiscoverHandler(db, hub)
					baseURL := cfg.Server.BaseURL
					if baseURL == "" {
						baseURL = fmt.Sprintf("http://localhost:%d", cfg.Server.Port)
					}
					uploadHandler := handlers.NewUploadHandler(db, uploadDir, baseURL, s3Storage)
					settingMgmt.GET("", settingHandler.GetAllSettings)
					settingMgmt.GET("/sms-gateway/config", smsSettingsHandler.GetSmsGatewayConfig)
					settingMgmt.PUT("/sms-gateway/config", middleware.RequireWriteRole(), smsSettingsHandler.SaveSmsGatewayConfig)
					settingMgmt.GET("/:key", settingHandler.GetSetting)
					settingMgmt.PUT("", middleware.RequireWriteRole(), settingHandler.UpdateSettings)
					settingMgmt.GET("/official-users", settingHandler.GetOfficialUsers)
					settingMgmt.GET("/official-users/:id/invitees", settingHandler.GetOfficialUserInvitees)
					settingMgmt.POST("/official-users", middleware.RequireWriteRole(), settingHandler.AddOfficialUser)
					settingMgmt.PUT("/official-users/:id", middleware.RequireWriteRole(), settingHandler.UpdateOfficialUser)
					settingMgmt.DELETE("/official-users/:id", middleware.RequireWriteRole(), settingHandler.RemoveOfficialUser)
					settingMgmt.GET("/official-groups", settingHandler.GetOfficialGroups)
					settingMgmt.POST("/official-groups", middleware.RequireWriteRole(), settingHandler.AddOfficialGroup)
					settingMgmt.DELETE("/official-groups/:id", middleware.RequireWriteRole(), settingHandler.RemoveOfficialGroup)
					settingMgmt.GET("/official-channels", settingHandler.GetOfficialChannels)
					settingMgmt.POST("/official-channels", middleware.RequireWriteRole(), settingHandler.AddOfficialChannel)
					settingMgmt.DELETE("/official-channels/:id", middleware.RequireWriteRole(), settingHandler.RemoveOfficialChannel)
					settingMgmt.GET("/discover-items", discoverHandler.ListDiscoverItems)
					settingMgmt.POST("/discover-items", middleware.RequireWriteRole(), discoverHandler.CreateDiscoverItem)
					settingMgmt.PUT("/discover-items/:id", middleware.RequireWriteRole(), discoverHandler.UpdateDiscoverItem)
					settingMgmt.DELETE("/discover-items/:id", middleware.RequireWriteRole(), discoverHandler.DeleteDiscoverItem)
					settingMgmt.POST("/discover-items/upload-icon", middleware.RequireWriteRole(), uploadHandler.UploadDiscoverIcon)
				}

				hotUpdateMgmt := adminAuth.Group("/hot-update")
				{
					hotUpdateHandler := handlers.NewHotUpdateHandler(db)
					hotUpdateMgmt.GET("/patches", hotUpdateHandler.ListPatches)
					hotUpdateMgmt.GET("/patches/:id", hotUpdateHandler.GetPatch)
					hotUpdateMgmt.GET("/reports", hotUpdateHandler.ListPatchReports)
					hotUpdateMgmt.POST("/patches", middleware.RequireWriteRole(), hotUpdateHandler.CreatePatch)
					hotUpdateMgmt.PUT("/patches/:id", middleware.RequireWriteRole(), hotUpdateHandler.UpdatePatch)
					hotUpdateMgmt.DELETE("/patches/:id", middleware.RequireWriteRole(), hotUpdateHandler.DeletePatch)
					hotUpdateMgmt.POST("/patches/:id/publish", middleware.RequireWriteRole(), hotUpdateHandler.PublishPatch)
					hotUpdateMgmt.POST("/patches/:id/pause", middleware.RequireWriteRole(), hotUpdateHandler.PausePatch)
					hotUpdateMgmt.POST("/patches/:id/rollback", middleware.RequireWriteRole(), hotUpdateHandler.RollbackPatch)
				}

				broadcastHandler := handlers.NewBroadcastHandler(hub, db)
				adminAuth.POST("/broadcast", middleware.RequireWriteRole(), broadcastHandler.SendBroadcast)
				adminAuth.GET("/broadcast/list", broadcastHandler.ListBroadcasts)
				adminAuth.DELETE("/broadcast/clear", middleware.RequireWriteRole(), broadcastHandler.ClearBroadcasts)

				popupAnnMgmtHandler := handlers.NewPopupAnnouncementHandler(db)
				adminAuth.GET("/popup-announcements", popupAnnMgmtHandler.AdminListPopupAnnouncements)
				adminAuth.POST("/popup-announcements", middleware.RequireWriteRole(), popupAnnMgmtHandler.AdminCreatePopupAnnouncement)
				adminAuth.PUT("/popup-announcements/:id", middleware.RequireWriteRole(), popupAnnMgmtHandler.AdminUpdatePopupAnnouncement)
				adminAuth.DELETE("/popup-announcements/:id", middleware.RequireWriteRole(), popupAnnMgmtHandler.AdminDeletePopupAnnouncement)

				emojiStoreAdmin := adminAuth.Group("/emoji-store")
				{
					emojiStoreAdminHandler := handlers.NewEmojiStoreAdminHandler(db)
					emojiStoreAdmin.GET("/packs", emojiStoreAdminHandler.ListPacks)
					emojiStoreAdmin.POST("/packs", middleware.RequireWriteRole(), emojiStoreAdminHandler.CreatePack)
					emojiStoreAdmin.PUT("/packs/:id", middleware.RequireWriteRole(), emojiStoreAdminHandler.UpdatePack)
					emojiStoreAdmin.PUT("/packs/:id/active", middleware.RequireWriteRole(), emojiStoreAdminHandler.SetPackActive)
					emojiStoreAdmin.DELETE("/packs/:id", middleware.RequireWriteRole(), emojiStoreAdminHandler.DeletePack)
				}

				msgAdminHandler := handlers.NewMessageAdminHandler(db, mongoDB)
				handlers.AdminHubInstance = hub
				adminAuth.GET("/messages/search", msgAdminHandler.SearchMessages)
				adminAuth.DELETE("/messages/delete", msgAdminHandler.DeleteAdminMessage)

				walletMgmt := adminAuth.Group("/wallet")
				{
					walletAdminHandler := handlers.NewWalletAdminHandler(db, cfg, onlinePaySvc)
					membershipAdminHandler := handlers.NewMembershipAdminHandler(db)
					walletMgmt.GET("/stats", walletAdminHandler.GetWalletStats)
					walletMgmt.GET("/users", walletAdminHandler.ListUserWallets)
					walletMgmt.GET("/user/:user_id", walletAdminHandler.GetUserWallet)
					walletMgmt.GET("/user/:user_id/transactions", walletAdminHandler.GetUserTransactions)
					walletMgmt.POST("/user/:user_id/balance", middleware.RequireWriteRole(), walletAdminHandler.UpdateUserBalance)
					walletMgmt.POST("/user/:user_id/reset-pay-password", middleware.RequireWriteRole(), walletAdminHandler.ResetUserPayPassword)
					walletMgmt.POST("/user/:user_id/clear-pay-password", middleware.RequireWriteRole(), walletAdminHandler.ClearUserPayPassword)
					walletMgmt.POST("/user/:user_id/lock", middleware.RequireWriteRole(), walletAdminHandler.LockUserWallet)
					walletMgmt.POST("/user/:user_id/unlock", middleware.RequireWriteRole(), walletAdminHandler.UnlockUserWallet)
					walletMgmt.GET("/withdraw/list", walletAdminHandler.ListWithdrawRequests)
					walletMgmt.GET("/withdraw/stats", walletAdminHandler.GetWithdrawStats)
					walletMgmt.POST("/withdraw/:id/review", middleware.RequireWriteRole(), walletAdminHandler.ReviewWithdrawRequest)
					walletMgmt.GET("/methods", walletAdminHandler.ListWithdrawMethods)
					walletMgmt.POST("/methods", middleware.RequireWriteRole(), walletAdminHandler.CreateWithdrawMethod)
					walletMgmt.PUT("/methods/:id", middleware.RequireWriteRole(), walletAdminHandler.UpdateWithdrawMethod)
					walletMgmt.DELETE("/methods/:id", middleware.RequireWriteRole(), walletAdminHandler.DeleteWithdrawMethod)
					walletMgmt.GET("/red-packets", walletAdminHandler.ListRedPackets)
					walletMgmt.GET("/red-packets/:id", walletAdminHandler.GetRedPacketDetail)
					walletMgmt.POST("/red-packets/:id/refund", middleware.RequireWriteRole(), walletAdminHandler.RefundRedPacket)
					walletMgmt.GET("/transfers", walletAdminHandler.ListTransfers)
					walletMgmt.GET("/transfers/:id", walletAdminHandler.GetTransferDetail)
					walletMgmt.POST("/transfers/:id/refund", middleware.RequireWriteRole(), walletAdminHandler.RefundTransfer)
					walletMgmt.GET("/settings", walletAdminHandler.GetWalletSettings)
					walletMgmt.POST("/settings", middleware.RequireWriteRole(), walletAdminHandler.SaveWalletSettings)
					walletMgmt.GET("/payment-config", walletAdminHandler.GetPaymentGatewayConfig)
					walletMgmt.PUT("/payment-config", middleware.RequireWriteRole(), walletAdminHandler.SavePaymentGatewayConfig)
					walletMgmt.GET("/recharge-methods", walletAdminHandler.ListRechargeMethods)
					walletMgmt.POST("/recharge-methods", middleware.RequireWriteRole(), walletAdminHandler.CreateRechargeMethod)
					walletMgmt.PUT("/recharge-methods/:id", middleware.RequireWriteRole(), walletAdminHandler.UpdateRechargeMethod)
					walletMgmt.DELETE("/recharge-methods/:id", middleware.RequireWriteRole(), walletAdminHandler.DeleteRechargeMethod)
					walletMgmt.GET("/recharge-orders", walletAdminHandler.ListRechargeOrders)
					walletMgmt.POST("/recharge-orders/:id/review", middleware.RequireWriteRole(), walletAdminHandler.ReviewRechargeOrder)
					walletMgmt.GET("/membership/summary", membershipAdminHandler.GetSummary)
					walletMgmt.GET("/membership/plans", membershipAdminHandler.ListPlans)
					walletMgmt.POST("/membership/plans", middleware.RequireWriteRole(), membershipAdminHandler.SavePlan)
					walletMgmt.GET("/membership/users", membershipAdminHandler.ListUserMemberships)
					walletMgmt.POST("/membership/user/:user_id/grant", middleware.RequireWriteRole(), membershipAdminHandler.GrantMembership)
					walletMgmt.POST("/membership/:id/cancel", middleware.RequireWriteRole(), membershipAdminHandler.CancelMembership)
					walletMgmt.GET("/membership/orders", membershipAdminHandler.ListOrders)
				}

				callMgmt := adminAuth.Group("/calls")
				{
					callAdminHandler := handlers.NewCallAdminHandler(db)
					callMgmt.GET("/list", callAdminHandler.ListCalls)
					callMgmt.GET("/stats", callAdminHandler.GetCallStats)
					callMgmt.GET("/:id", callAdminHandler.GetCallDetail)
					callMgmt.GET("/user/:user_id", callAdminHandler.GetUserCallHistory)
					callMgmt.DELETE("/:id", middleware.RequireWriteRole(), callAdminHandler.DeleteCall)
					callMgmt.POST("/batch-delete", middleware.RequireWriteRole(), callAdminHandler.BatchDeleteCalls)
				}
			}
		}

		appAPI := api.Group("/app")
		{
			settingHandler := handlers.NewSettingHandler(db)
			hotUpdateHandler := handlers.NewHotUpdateHandler(db)
			discoverHandler := handlers.NewDiscoverHandler(db, hub)
			broadcastAppHandler := handlers.NewBroadcastHandler(hub, db)
			appAPI.GET("/settings", settingHandler.GetAppSettings)
			appAPI.GET("/hot-update/check", hotUpdateHandler.CheckPatch)
			appAPI.POST("/hot-update/report", middleware.OptionalAuth(cache), hotUpdateHandler.ReportPatchResult)
			appAPI.GET("/discovery", discoverHandler.GetAppDiscoverItems)
			appAPI.GET("/check-official/user/:uuid", settingHandler.CheckUserOfficial)
			appAPI.GET("/check-official/chat/:uuid", settingHandler.CheckChatOfficial)
			appAPI.GET("/broadcasts", broadcastAppHandler.GetRecentBroadcasts)
			appAPI.GET("/user-agreement", settingHandler.GetUserAgreement)
			appAPI.GET("/privacy-policy", settingHandler.GetPrivacyPolicy)
		}

		userSettings := api.Group("/user-settings")
		userSettings.Use(middleware.Auth(cache), middleware.RequirePhoneBind(db, cache))
		{
			settingHandler := handlers.NewSettingHandler(db)
			userSettings.POST("/sync-official-contacts", settingHandler.SyncOfficialContacts)
			userSettings.GET("/official-service/profile", settingHandler.GetMyOfficialServiceProfile)
			userSettings.PUT("/official-service/profile", settingHandler.UpdateMyOfficialServiceProfile)
		}
	}

	return router
}
