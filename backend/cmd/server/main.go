package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/config"
	"gaoranim/internal/handlers"
	"gaoranim/internal/middleware"
	"gaoranim/internal/models"
	"gaoranim/internal/mq"
	"gaoranim/internal/services"
	"gaoranim/internal/ws"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
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

	// 7. 初始化消息队列
	mqService := mq.NewMessageQueue(redisClient, cfg.MessageQueue.Workers)

	// 8. 初始化服务
	msgService := services.NewMessageService(mongoDB, mysqlDB, cacheService, mqService, hub)
	pushService := services.NewPushService(mysqlDB)
	services.RegisterMessageQueueHandlers(mqService, pushService)
	mqService.Start(mq.QueueMessageSend, mq.QueueMessageSync, mq.QueuePushNotify)
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

	// 12. 初始化路由
	router := setupRouter(cfg, mysqlDB, mongoDB, cacheService, hub, msgService, pushService)

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

	// 自动迁移
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
		// 动态相关
		&models.Moment{},
		&models.MomentLike{},
		&models.MomentComment{},
		&models.Topic{},
		&models.BannedWord{},
		&models.MomentBlock{},     // 屏蔽的动态
		&models.UserMomentBlock{}, // 屏蔽用户的动态
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
		&models.UserPushSetting{}, // 用户推送设置
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
		// 邀请码
		&models.InviteCode{},
		&models.InviteCodeUsage{},
	); err != nil {
		return nil, err
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

	// 修复群组成员角色数据
	fixChatMemberRoles(db)

	// 初始化默认管理员
	if err := initDefaultAdmin(db, serverMode); err != nil {
		return nil, err
	}

	// 加载心跳超时设置
	loadHeartbeatTimeout(db)

	return db, nil
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

// backfillUserShortIDs 为历史数据补齐 short_id，保证“平台短号搜索”可用
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

	return client.Database(cfg.Database), nil
}

// initRedis 初始化Redis连接
func initRedis(cfg config.RedisConfig) (*redis.Client, error) {
	client := redis.NewClient(&redis.Options{
		Addr:         cfg.Addr,
		Password:     cfg.Password,
		DB:           cfg.DB,
		PoolSize:     cfg.PoolSize,
		MinIdleConns: cfg.MinIdleConns,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, err
	}

	return client, nil
}

// setupRouter 设置路由
func setupRouter(
	cfg *config.Config,
	db *gorm.DB,
	mongoDB *mongo.Database,
	cache *cache.Cache,
	hub *ws.Hub,
	msgService *services.MessageService,
	pushService *services.PushService,
) *gin.Engine {
	router := gin.New()

	// 中间件
	router.Use(gin.Recovery())
	router.Use(middleware.Logger())
	router.Use(middleware.CORS())
	router.Use(middleware.RateLimit(cache))

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
	uploads.StaticFS("/", gin.Dir(uploadDir, false))

	// 根路径：访问 / 时提示后端已启动
	router.GET("/", func(c *gin.Context) {
		c.String(200, "壹信IM后端启动成功")
	})
	router.GET("/favicon.ico", func(c *gin.Context) { c.Status(204) })
	router.GET("/robots.txt", func(c *gin.Context) {
		c.Data(200, "text/plain; charset=utf-8", []byte("User-agent: *\nDisallow: /\n"))
	})

	// 健康检查
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status": "ok",
			"time":   time.Now().Unix(),
		})
	})

	// WebSocket状态
	router.GET("/ws/stats", func(c *gin.Context) {
		c.JSON(200, hub.GetStats())
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
			authHandler := handlers.NewAuthHandler(db, cache, msgService, smsSvc)
			qrLoginHandler := handlers.NewQRLoginHandler(db, cache)
			auth.POST("/login", authHandler.Login)
			auth.POST("/register", authHandler.Register)
			auth.POST("/check-username", authHandler.CheckUsername)
			auth.POST("/password/send-reset-code", authHandler.SendPasswordResetCode)
			auth.POST("/password/reset-by-code", authHandler.ResetPasswordByCode)
			auth.POST("/device-lock/verify", authHandler.VerifyDeviceLockLogin)
			auth.POST("/qr-login/create", qrLoginHandler.Create)
			auth.GET("/qr-login/status/:ticket", qrLoginHandler.GetStatus)
			auth.POST("/qr-login/confirm/:ticket", middleware.Auth(cache), middleware.RequirePhoneBind(db), qrLoginHandler.Confirm)
			auth.POST("/refresh", authHandler.RefreshToken)
			auth.POST("/logout", middleware.Auth(cache), authHandler.Logout)
			auth.POST("/change-password", middleware.Auth(cache), middleware.RequirePhoneBind(db), authHandler.ChangePassword)
		}

		// 需要认证的路由
		authorized := api.Group("")
		authorized.Use(middleware.Auth(cache), middleware.RequirePhoneBind(db))
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
				user.GET("/search-all", userHandler.SearchAll) // 搜索用户和公开群组/频道
				// 隐私设置（放在 /:id 前面避免路由冲突）
				user.GET("/privacy", userHandler.GetPrivacySettings)
				user.PUT("/privacy", userHandler.UpdatePrivacySettings)
				user.POST("/two-step", userHandler.UpdateTwoStep)
				// 表情商店云同步
				user.GET("/emoji-store/catalog", userHandler.GetEmojiStoreCatalog)
				user.GET("/emoji-store", userHandler.GetEmojiStore)
				user.PUT("/emoji-store", userHandler.UpdateEmojiStore)
				// 屏蔽用户
				user.GET("/blocked", userHandler.GetBlockedUsers)
				user.GET("/blocked/check", userHandler.CheckBlockStatus)
				user.POST("/blocked", userHandler.BlockUser)
				user.DELETE("/blocked/:blocked_id", userHandler.UnblockUser)
				// 会话管理
				user.GET("/sessions", userHandler.GetSessions)
				user.POST("/sessions/terminate-others", userHandler.TerminateOtherSessions)
				user.DELETE("/sessions/:session_id", userHandler.TerminateSession)
				// 设备管理
				user.GET("/devices", userHandler.GetDevices)
				user.DELETE("/devices/:device_id", userHandler.TerminateDevice)
				user.POST("/devices/terminate-others", userHandler.TerminateOtherDevices)
				// 推送通知
				user.POST("/push-token", userHandler.UpdatePushToken)
				user.DELETE("/push-token", userHandler.DeletePushToken)
				user.PUT("/push-settings", userHandler.UpdatePushSettings)
				user.GET("/push-settings", userHandler.GetPushSettings)
				// 账号管理
				user.DELETE("/account", userHandler.DeleteAccount)
				// 用户查询（放在最后）
				user.GET("/:id", userHandler.GetUser)
				user.GET("/:id/common-groups", userHandler.GetCommonGroups)
			}

			// 会话
			chat := authorized.Group("/chat")
			{
				chatHandler := handlers.NewChatHandler(db, cache, hub, msgService)
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
				// 加入请求审批
				chat.GET("/:id/join-requests", chatHandler.GetJoinRequests)
				chat.POST("/:id/join-requests/:request_id/review", chatHandler.ReviewJoinRequest)
				// 禁言功能
				chat.POST("/:id/mute", chatHandler.MuteMember)
				chat.POST("/:id/unmute", chatHandler.UnmuteMember)
				chat.GET("/:id/mute-status", chatHandler.GetMemberMuteStatus)
				// 会话操作（置顶、静音、未读）
				chat.POST("/:id/pin", chatHandler.TogglePin)
				chat.POST("/:id/mute-chat", chatHandler.ToggleMuteChat)
				chat.POST("/:id/toggle-unread", chatHandler.ToggleUnread)
				// 消息置顶
				pinHandler := handlers.NewPinHandler(db, mongoDB, hub)
				chat.POST("/:id/pin-message", pinHandler.PinMessage)
				chat.DELETE("/:id/pin-message", pinHandler.UnpinMessage)
				chat.GET("/:id/pin-message", pinHandler.GetPinnedMessage)
				// 群公告
				announcementHandler := handlers.NewAnnouncementHandler(db, hub)
				chat.GET("/:id/announcements", announcementHandler.GetAnnouncements)
				chat.POST("/:id/announcements", announcementHandler.CreateAnnouncement)
				chat.PUT("/:id/announcements/:announcement_id", announcementHandler.UpdateAnnouncement)
				chat.DELETE("/:id/announcements/:announcement_id", announcementHandler.DeleteAnnouncement)
				// 清空聊天记录和搜索消息
				chat.POST("/:id/clear", chatHandler.ClearChatHistory)
				chat.POST("/:id/clear-both", chatHandler.ClearChatHistoryForBoth)
				chat.GET("/:id/search", chatHandler.SearchMessages)
			}

			// 消息
			message := authorized.Group("/message")
			{
				msgHandler := handlers.NewMessageHandler(db, msgService, pushService, hub, cache)
				message.GET("/e2ee/device-keys", msgHandler.GetChatDeviceKeys)
				message.POST("/send", msgHandler.SendMessage)
				message.GET("/list", msgHandler.GetMessages)
				message.POST("/revoke", msgHandler.RevokeMessage)
				message.POST("/delete", msgHandler.DeleteMessage)
				message.POST("/sync", msgHandler.SyncMessages)
				message.POST("/read", msgHandler.MarkAsRead)
				// 表情回复
				message.POST("/reaction/add", msgHandler.AddReaction)
				message.POST("/reaction/remove", msgHandler.RemoveReaction)
				// 转发和编辑
				message.POST("/forward", msgHandler.ForwardMessage)
				message.POST("/edit", msgHandler.EditMessage)
				// 媒体/文件/链接列表
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
				// 我的动态相关
				moment.GET("/my/moments", momentHandler.GetMyMoments)
				moment.GET("/my/likes", momentHandler.GetMyLikes)
				moment.GET("/my/comments", momentHandler.GetMyComments)
				moment.GET("/my/received-likes", momentHandler.GetReceivedLikes) // 收到的点赞
				moment.GET("/search", momentHandler.SearchMoments)
				// 屏蔽相关
				moment.POST("/:id/block", momentHandler.BlockMoment)        // 屏蔽动态
				moment.POST("/block-user/:userId", momentHandler.BlockUser) // 屏蔽用户动态
			}

			// 音视频通话（声网）
			call := authorized.Group("/call")
			{
				// 初始化声网服务
				agoraService := services.NewAgoraService(
					cfg.Agora.Enabled,
					cfg.Agora.AppID,
					cfg.Agora.AppCertificate,
					cfg.Agora.TokenExpire,
				)
				// 将 ws.Hub 转为 services.WebSocketHub 接口
				callHandler := handlers.NewCallHandler(db, agoraService, hub, msgService, pushService)
				call.GET("/config", callHandler.GetAgoraConfig)  // 获取声网配置
				call.GET("/token", callHandler.GetToken)         // 获取Token
				call.POST("/create", callHandler.CreateCall)     // 发起通话
				call.POST("/accept", callHandler.AcceptCall)     // 接听通话
				call.POST("/reject", callHandler.RejectCall)     // 拒绝通话
				call.POST("/end", callHandler.EndCall)           // 结束通话
				call.DELETE("/:call_id", callHandler.CancelCall) // 取消通话
				call.GET("/history", callHandler.GetCallHistory) // 通话记录
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
				meeting.POST("/create", meetingHandler.CreateMeeting) // 创建会议
				meeting.POST("/join", meetingHandler.JoinMeeting)     // 加入会议
				meeting.POST("/join-request/review", meetingHandler.ReviewJoinRequest)
				meeting.POST("/title", meetingHandler.UpdateMeetingTitle)   // 修改会议名称
				meeting.POST("/leave", meetingHandler.LeaveMeeting)         // 离开会议
				meeting.POST("/invite", meetingHandler.InviteMembers)       // 邀请成员
				meeting.POST("/end", meetingHandler.EndMeeting)             // 结束会议
				meeting.POST("/member/mute", meetingHandler.MuteMember)     // 会中静音成员
				meeting.POST("/member/kick", meetingHandler.KickMember)     // 会中移出成员
				meeting.POST("/host/transfer", meetingHandler.TransferHost) // 转移主持人
				meeting.GET("/token", meetingHandler.GetToken)              // 获取会议 Token
				meeting.GET("/detail", meetingHandler.GetMeetingDetail)     // 会议详情
				meeting.GET("/active", meetingHandler.GetActiveMeeting)
			}

			// 文件上传
			upload := authorized.Group("/upload")
			{
				// 优先使用配置的 BaseURL，如果未配置则使用本地地址
				baseURL := cfg.Server.BaseURL
				if baseURL == "" {
					baseURL = fmt.Sprintf("http://localhost:%d", cfg.Server.Port)
				}
				uploadHandler := handlers.NewUploadHandler(db, uploadDir, baseURL)
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
				wrl5 := middleware.WalletRateLimit(cache, 5, time.Minute)   // 5次/分钟
				wrl10 := middleware.WalletRateLimit(cache, 10, time.Minute) // 10次/分钟
				wallet.GET("/online-pay/options", onlinePayHandler.Options)
				wallet.POST("/online-pay/create", wrl5, onlinePayHandler.Create)
				wallet.GET("/online-pay/order/:out_trade_no", onlinePayHandler.QueryOrder)
				wallet.GET("", walletHandler.GetWallet)                                 // 获取钱包信息
				wallet.GET("/membership", membershipHandler.GetMyMembership)            // 获取我的会员信息
				wallet.GET("/membership/plans", membershipHandler.ListPlans)            // 获取会员套餐
				wallet.POST("/membership/purchase", wrl5, membershipHandler.Purchase)   // 购买会员
				wallet.GET("/settings", walletHandler.GetWalletSettings)                // 获取钱包设置
				wallet.GET("/recharge-methods", walletHandler.GetRechargeMethods)       // 获取充值方式列表
				wallet.POST("/recharge-order", wrl5, walletHandler.CreateRechargeOrder) // 提交充值订单
				wallet.GET("/recharge-orders", walletHandler.GetRechargeOrders)         // 查询充值订单
				wallet.POST("/pay-password", walletHandler.SetPayPassword)              // 设置/修改支付密码
				wallet.POST("/verify-password", walletHandler.VerifyPayPassword)        // 验证支付密码
				wallet.GET("/transactions", walletHandler.GetTransactions)              // 交易记录
				wallet.POST("/recharge", wrl5, walletHandler.Recharge)                  // 充值（限流）
				// 红包
				wallet.POST("/red-packet/send", wrl5, walletHandler.SendRedPacket)        // 发红包（限流）
				wallet.POST("/red-packet/:id/claim", wrl10, walletHandler.ClaimRedPacket) // 领取红包（限流）
				wallet.GET("/red-packet/:id", walletHandler.GetRedPacket)                 // 红包详情
				// 转账
				wallet.POST("/transfer/send", wrl5, walletHandler.SendTransfer)         // 发起转账（限流）
				wallet.POST("/transfer/:id/accept", wrl5, walletHandler.AcceptTransfer) // 接收转账（限流）
				wallet.POST("/transfer/:id/reject", wrl5, walletHandler.RejectTransfer) // 拒收转账（限流）
				wallet.GET("/transfer/:id", walletHandler.GetTransfer)                  // 转账详情
				// 提现
				wallet.GET("/withdraw/methods", walletHandler.GetWithdrawMethods)   // 获取提现方式
				wallet.POST("/withdraw", wrl5, walletHandler.CreateWithdrawRequest) // 发起提现（限流）
			}
		}

		// WebSocket连接
		api.GET("/ws", middleware.Auth(cache), middleware.RequirePhoneBind(db), handlers.HandleWebSocket(hub, cfg.WebSocket, db))

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
			adminHandler := handlers.NewAdminHandler(db)

			// 管理员登录（无需认证）
			adminAPI.POST("/login", adminHandler.Login)

			// 需要管理员认证的路由
			adminAuth := adminAPI.Group("")
			adminAuth.Use(middleware.AdminAuth())
			{
				// 当前管理员
				adminAuth.GET("/me", adminHandler.GetCurrentAdmin)
				adminAuth.PUT("/password", adminHandler.UpdatePassword)

				// 管理员管理（仅超级管理员）
				adminAuth.GET("/list", middleware.RequireRole("super_admin"), adminHandler.ListAdmins)
				adminAuth.POST("/create", middleware.RequireRole("super_admin"), adminHandler.CreateAdmin)
				adminAuth.DELETE("/:id", middleware.RequireRole("super_admin"), adminHandler.DeleteAdmin)

				// 用户管理
				userMgmt := adminAuth.Group("/users")
				{
					userMgmtHandler := handlers.NewUserMgmtHandler(db, hub, cache, pushService)
					userMgmt.GET("/list", userMgmtHandler.ListUsers)
					userMgmt.GET("/stats", userMgmtHandler.GetUserStats)
					userMgmt.GET("/:id/diagnostics", userMgmtHandler.GetUserDiagnostics)
					// 写操作需要非演示管理员权限
					userMgmt.PUT("/:id", middleware.RequireWriteRole(), userMgmtHandler.UpdateUser)
					userMgmt.PUT("/:id/status", middleware.RequireWriteRole(), userMgmtHandler.UpdateUserStatus)
					userMgmt.POST("/:id/kick", middleware.RequireWriteRole(), userMgmtHandler.KickUser)
					userMgmt.POST("/:id/ban", middleware.RequireWriteRole(), userMgmtHandler.BanUser)
					userMgmt.POST("/:id/unban", middleware.RequireWriteRole(), userMgmtHandler.UnbanUser)
					userMgmt.POST("/:id/freeze", middleware.RequireWriteRole(), userMgmtHandler.FreezeUser)
					userMgmt.POST("/:id/unfreeze", middleware.RequireWriteRole(), userMgmtHandler.UnfreezeUser)
					userMgmt.POST("/:id/reset-password", middleware.RequireWriteRole(), userMgmtHandler.ResetUserPassword)
					userMgmt.POST("/:id/test-push", middleware.RequireWriteRole(), userMgmtHandler.SendTestPush)
				}

				// 会话管理
				chatMgmt := adminAuth.Group("/chats")
				{
					chatMgmtHandler := handlers.NewChatMgmtHandler(db)
					chatMgmt.GET("/list", chatMgmtHandler.ListChats)
					chatMgmt.GET("/groups", chatMgmtHandler.ListGroups)
					chatMgmt.GET("/channels", chatMgmtHandler.ListChannels)
					chatMgmt.GET("/stats", chatMgmtHandler.GetChatStats)
					chatMgmt.GET("/:id", chatMgmtHandler.GetChatDetail)
					chatMgmt.GET("/:id/members", chatMgmtHandler.GetChatMembers)
					// 写操作需要非演示管理员权限
					chatMgmt.PUT("/:id/status", middleware.RequireWriteRole(), chatMgmtHandler.UpdateChatStatus)
					chatMgmt.POST("/:id/ban", middleware.RequireWriteRole(), chatMgmtHandler.BanChat)
					chatMgmt.POST("/:id/unban", middleware.RequireWriteRole(), chatMgmtHandler.UnbanChat)
					chatMgmt.POST("/:id/dissolve", middleware.RequireWriteRole(), chatMgmtHandler.DissolveChat)
					chatMgmt.DELETE("/:id", middleware.RequireWriteRole(), chatMgmtHandler.DeleteChat)
					chatMgmt.DELETE("/:id/members/:member_id", middleware.RequireWriteRole(), chatMgmtHandler.RemoveChatMember)
				}

				// 统计数据
				stats := adminAuth.Group("/stats")
				{
					statsHandler := handlers.NewStatsHandler(db, mongoDB, cache)
					stats.GET("/dashboard", statsHandler.GetDashboardStats)
					stats.GET("/runtime", statsHandler.GetRuntimeStatus)
					stats.GET("/users", statsHandler.GetUserStats)
					stats.GET("/messages", statsHandler.GetMessageStats)
				}

				// 动态管理
				momentMgmt := adminAuth.Group("/moments")
				{
					momentMgmtHandler := handlers.NewMomentMgmtHandler(db)
					momentMgmt.GET("/list", momentMgmtHandler.ListMoments)
					momentMgmt.GET("/stats", momentMgmtHandler.GetMomentStats)
					// 写操作需要非演示管理员权限
					momentMgmt.PUT("/:id/status", middleware.RequireWriteRole(), momentMgmtHandler.UpdateMomentStatus)
					momentMgmt.DELETE("/:id", middleware.RequireWriteRole(), momentMgmtHandler.DeleteMoment)
				}

				// 话题管理
				topicMgmt := adminAuth.Group("/topics")
				{
					momentMgmtHandler := handlers.NewMomentMgmtHandler(db)
					topicMgmt.GET("/list", momentMgmtHandler.ListTopics)
					// 写操作需要非演示管理员权限
					topicMgmt.POST("/create", middleware.RequireWriteRole(), momentMgmtHandler.CreateTopic)
					topicMgmt.PUT("/:id", middleware.RequireWriteRole(), momentMgmtHandler.UpdateTopic)
					topicMgmt.DELETE("/:id", middleware.RequireWriteRole(), momentMgmtHandler.DeleteTopic)
				}

				// 违禁词管理
				bannedMgmt := adminAuth.Group("/banned-words")
				{
					momentMgmtHandler := handlers.NewMomentMgmtHandler(db)
					bannedMgmt.GET("/list", momentMgmtHandler.ListBannedWords)
					// 写操作需要非演示管理员权限
					bannedMgmt.POST("/create", middleware.RequireWriteRole(), momentMgmtHandler.CreateBannedWord)
					bannedMgmt.POST("/batch", middleware.RequireWriteRole(), momentMgmtHandler.BatchCreateBannedWords)
					bannedMgmt.PUT("/:id", middleware.RequireWriteRole(), momentMgmtHandler.UpdateBannedWord)
					bannedMgmt.DELETE("/:id", middleware.RequireWriteRole(), momentMgmtHandler.DeleteBannedWord)
				}

				// 举报管理
				reportMgmt := adminAuth.Group("/reports")
				{
					reportHandler := handlers.NewReportHandler(db)
					reportMgmt.GET("/list", reportHandler.ListReports)
					reportMgmt.GET("/stats", reportHandler.GetReportStats)
					// 写操作需要非演示管理员权限
					reportMgmt.POST("/:id/process", middleware.RequireWriteRole(), reportHandler.ProcessReport)
					reportMgmt.DELETE("/:id", middleware.RequireWriteRole(), reportHandler.DeleteReport)
				}

				// 系统设置
				settingMgmt := adminAuth.Group("/settings")
				{
					settingHandler := handlers.NewSettingHandler(db, pushService)
					settingHandler.SetSMSService(smsSvc)
					smsSettingsHandler := handlers.NewSmsSettingsHandler(db, cfg, smsSvc)
					discoverHandler := handlers.NewDiscoverHandler(db, hub)
					baseURL := cfg.Server.BaseURL
					if baseURL == "" {
						baseURL = fmt.Sprintf("http://localhost:%d", cfg.Server.Port)
					}
					uploadHandler := handlers.NewUploadHandler(db, uploadDir, baseURL)
					settingMgmt.GET("", settingHandler.GetAllSettings)
					settingMgmt.GET("/sms-gateway/config", smsSettingsHandler.GetSmsGatewayConfig)
					settingMgmt.PUT("/sms-gateway/config", middleware.RequireWriteRole(), smsSettingsHandler.SaveSmsGatewayConfig)
					settingMgmt.GET("/:key", settingHandler.GetSetting)
					// 写操作需要非演示管理员权限
					settingMgmt.PUT("", middleware.RequireWriteRole(), settingHandler.UpdateSettings)
					// 官方用户管理
					settingMgmt.GET("/official-users", settingHandler.GetOfficialUsers)
					settingMgmt.GET("/official-users/:id/invitees", settingHandler.GetOfficialUserInvitees)
					settingMgmt.POST("/official-users", middleware.RequireWriteRole(), settingHandler.AddOfficialUser)
					settingMgmt.PUT("/official-users/:id", middleware.RequireWriteRole(), settingHandler.UpdateOfficialUser)
					settingMgmt.DELETE("/official-users/:id", middleware.RequireWriteRole(), settingHandler.RemoveOfficialUser)
					// 官方群组管理
					settingMgmt.GET("/official-groups", settingHandler.GetOfficialGroups)
					settingMgmt.POST("/official-groups", middleware.RequireWriteRole(), settingHandler.AddOfficialGroup)
					settingMgmt.DELETE("/official-groups/:id", middleware.RequireWriteRole(), settingHandler.RemoveOfficialGroup)
					// 官方频道管理
					settingMgmt.GET("/official-channels", settingHandler.GetOfficialChannels)
					settingMgmt.POST("/official-channels", middleware.RequireWriteRole(), settingHandler.AddOfficialChannel)
					settingMgmt.DELETE("/official-channels/:id", middleware.RequireWriteRole(), settingHandler.RemoveOfficialChannel)
					// 发现页入口管理
					settingMgmt.GET("/discover-items", discoverHandler.ListDiscoverItems)
					settingMgmt.POST("/discover-items", middleware.RequireWriteRole(), discoverHandler.CreateDiscoverItem)
					settingMgmt.PUT("/discover-items/:id", middleware.RequireWriteRole(), discoverHandler.UpdateDiscoverItem)
					settingMgmt.DELETE("/discover-items/:id", middleware.RequireWriteRole(), discoverHandler.DeleteDiscoverItem)
					settingMgmt.POST("/discover-items/upload-icon", middleware.RequireWriteRole(), uploadHandler.UploadDiscoverIcon)
				}

				// 热更新补丁管理
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

				// 全局公告广播
				broadcastHandler := handlers.NewBroadcastHandler(hub, db)
				adminAuth.POST("/broadcast", middleware.RequireWriteRole(), broadcastHandler.SendBroadcast)
				adminAuth.GET("/broadcast/list", broadcastHandler.ListBroadcasts)
				adminAuth.DELETE("/broadcast/clear", middleware.RequireWriteRole(), broadcastHandler.ClearBroadcasts)

				// 表情商店目录管理
				emojiStoreAdmin := adminAuth.Group("/emoji-store")
				{
					emojiStoreAdminHandler := handlers.NewEmojiStoreAdminHandler(db)
					emojiStoreAdmin.GET("/packs", emojiStoreAdminHandler.ListPacks)
					emojiStoreAdmin.POST("/packs", middleware.RequireWriteRole(), emojiStoreAdminHandler.CreatePack)
					emojiStoreAdmin.PUT("/packs/:id", middleware.RequireWriteRole(), emojiStoreAdminHandler.UpdatePack)
					emojiStoreAdmin.PUT("/packs/:id/active", middleware.RequireWriteRole(), emojiStoreAdminHandler.SetPackActive)
					emojiStoreAdmin.DELETE("/packs/:id", middleware.RequireWriteRole(), emojiStoreAdminHandler.DeletePack)
				}

				// 消息搜索
				msgAdminHandler := handlers.NewMessageAdminHandler(db, mongoDB)
				adminAuth.GET("/messages/search", msgAdminHandler.SearchMessages)

				// 钱包管理
				walletMgmt := adminAuth.Group("/wallet")
				{
					walletAdminHandler := handlers.NewWalletAdminHandler(db, cfg, onlinePaySvc)
					membershipAdminHandler := handlers.NewMembershipAdminHandler(db)
					walletMgmt.GET("/stats", walletAdminHandler.GetWalletStats)
					// 用户钱包管理
					walletMgmt.GET("/users", walletAdminHandler.ListUserWallets)                                                                 // 获取钱包用户列表
					walletMgmt.GET("/user/:user_id", walletAdminHandler.GetUserWallet)                                                           // 查看用户钱包
					walletMgmt.GET("/user/:user_id/transactions", walletAdminHandler.GetUserTransactions)                                        // 查看用户资金记录
					walletMgmt.POST("/user/:user_id/balance", middleware.RequireWriteRole(), walletAdminHandler.UpdateUserBalance)               // 修改用户余额
					walletMgmt.POST("/user/:user_id/reset-pay-password", middleware.RequireWriteRole(), walletAdminHandler.ResetUserPayPassword) // 重置支付密码
					walletMgmt.POST("/user/:user_id/clear-pay-password", middleware.RequireWriteRole(), walletAdminHandler.ClearUserPayPassword) // 清除支付密码
					walletMgmt.POST("/user/:user_id/lock", middleware.RequireWriteRole(), walletAdminHandler.LockUserWallet)                     // 锁定钱包
					walletMgmt.POST("/user/:user_id/unlock", middleware.RequireWriteRole(), walletAdminHandler.UnlockUserWallet)                 // 解锁钱包
					// 提现申请管理
					walletMgmt.GET("/withdraw/list", walletAdminHandler.ListWithdrawRequests)
					walletMgmt.GET("/withdraw/stats", walletAdminHandler.GetWithdrawStats)
					walletMgmt.POST("/withdraw/:id/review", middleware.RequireWriteRole(), walletAdminHandler.ReviewWithdrawRequest)
					// 提现方式管理
					walletMgmt.GET("/methods", walletAdminHandler.ListWithdrawMethods)
					walletMgmt.POST("/methods", middleware.RequireWriteRole(), walletAdminHandler.CreateWithdrawMethod)
					walletMgmt.PUT("/methods/:id", middleware.RequireWriteRole(), walletAdminHandler.UpdateWithdrawMethod)
					walletMgmt.DELETE("/methods/:id", middleware.RequireWriteRole(), walletAdminHandler.DeleteWithdrawMethod)
					// 红包记录管理
					walletMgmt.GET("/red-packets", walletAdminHandler.ListRedPackets)
					walletMgmt.GET("/red-packets/:id", walletAdminHandler.GetRedPacketDetail)
					walletMgmt.POST("/red-packets/:id/refund", middleware.RequireWriteRole(), walletAdminHandler.RefundRedPacket)
					// 转账记录管理
					walletMgmt.GET("/transfers", walletAdminHandler.ListTransfers)
					walletMgmt.GET("/transfers/:id", walletAdminHandler.GetTransferDetail)
					walletMgmt.POST("/transfers/:id/refund", middleware.RequireWriteRole(), walletAdminHandler.RefundTransfer)
					// 钱包设置
					walletMgmt.GET("/settings", walletAdminHandler.GetWalletSettings)
					walletMgmt.POST("/settings", middleware.RequireWriteRole(), walletAdminHandler.SaveWalletSettings)
					walletMgmt.GET("/payment-config", walletAdminHandler.GetPaymentGatewayConfig)
					walletMgmt.PUT("/payment-config", middleware.RequireWriteRole(), walletAdminHandler.SavePaymentGatewayConfig)
					// 充值方式管理
					walletMgmt.GET("/recharge-methods", walletAdminHandler.ListRechargeMethods)
					walletMgmt.POST("/recharge-methods", middleware.RequireWriteRole(), walletAdminHandler.CreateRechargeMethod)
					walletMgmt.PUT("/recharge-methods/:id", middleware.RequireWriteRole(), walletAdminHandler.UpdateRechargeMethod)
					walletMgmt.DELETE("/recharge-methods/:id", middleware.RequireWriteRole(), walletAdminHandler.DeleteRechargeMethod)
					// 人工充值审核
					walletMgmt.GET("/recharge-orders", walletAdminHandler.ListRechargeOrders)
					walletMgmt.POST("/recharge-orders/:id/review", middleware.RequireWriteRole(), walletAdminHandler.ReviewRechargeOrder)
					// 会员管理
					walletMgmt.GET("/membership/summary", membershipAdminHandler.GetSummary)
					walletMgmt.GET("/membership/plans", membershipAdminHandler.ListPlans)
					walletMgmt.POST("/membership/plans", middleware.RequireWriteRole(), membershipAdminHandler.SavePlan)
					walletMgmt.GET("/membership/users", membershipAdminHandler.ListUserMemberships)
					walletMgmt.POST("/membership/user/:user_id/grant", middleware.RequireWriteRole(), membershipAdminHandler.GrantMembership)
					walletMgmt.POST("/membership/:id/cancel", middleware.RequireWriteRole(), membershipAdminHandler.CancelMembership)
					walletMgmt.GET("/membership/orders", membershipAdminHandler.ListOrders)
				}

				// 通话记录管理
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

		// App端公开接口（无需管理员权限）
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

		// 用户端需要认证的系统相关接口
		userSettings := api.Group("/user-settings")
		userSettings.Use(middleware.Auth(cache), middleware.RequirePhoneBind(db))
		{
			settingHandler := handlers.NewSettingHandler(db)
			userSettings.POST("/sync-official-contacts", settingHandler.SyncOfficialContacts)
			userSettings.GET("/official-service/profile", settingHandler.GetMyOfficialServiceProfile)
			userSettings.PUT("/official-service/profile", settingHandler.UpdateMyOfficialServiceProfile)
		}
	}

	return router
}
