// 文件用途：加载、规范化并校验后端运行配置。
// 核心逻辑：读取 YAML，应用环境变量覆盖和默认值，并检查生产安全边界。

package config

import (
	"fmt"
	"gopkg.in/yaml.v3"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Server          ServerConfig          `yaml:"server"`
	MySQL           MySQLConfig           `yaml:"mysql"`
	MongoDB         MongoDBConfig         `yaml:"mongodb"`
	Redis           RedisConfig           `yaml:"redis"`
	Cluster         ClusterConfig         `yaml:"cluster"`
	JWT             JWTConfig             `yaml:"jwt"`
	WebSocket       WebSocketConfig       `yaml:"websocket"`
	ClientBootstrap ClientBootstrapConfig `yaml:"client_bootstrap"`
	MessageQueue    MessageQueueConfig    `yaml:"message_queue"`
	MessageStorage  MessageStorageConfig  `yaml:"message_storage"`
	Shard           ShardConfig           `yaml:"shard"`
	Agora           AgoraConfig           `yaml:"agora"`
	LiveKit         LiveKitConfig         `yaml:"livekit"`
	Storage         StorageConfig         `yaml:"storage"`
	Payment         PaymentConfig         `yaml:"payment"`
	SMS             SMSConfig             `yaml:"sms"`
	Email           EmailConfig           `yaml:"email"`
}
type ServerConfig struct {
	Port                        int           `yaml:"port"`
	Mode                        string        `yaml:"mode"`
	ReadTimeout                 time.Duration `yaml:"read_timeout"`
	WriteTimeout                time.Duration `yaml:"write_timeout"`
	BaseURL                     string        `yaml:"base_url"`                       // 服务器外部访问地址
	RegisterBaseURL             string        `yaml:"register_base_url"`              // 注册页外部访问地址，留空则回退到 BaseURL
	UploadDir                   string        `yaml:"upload_dir"`                     // 上传文件存储目录，默认 ./uploads
	AllowedOrigins              []string      `yaml:"allowed_origins"`                // API CORS Origin 白名单；留空兼容所有来源
	ExternalCleanupHTTPDelete   bool          `yaml:"external_cleanup_http_delete"`   // 是否允许服务端对外链执行 HTTP DELETE（默认 false）
	ExternalCleanupAllowedHosts []string      `yaml:"external_cleanup_allowed_hosts"` // 允许执行外部清理的主机白名单
}
type MySQLConfig struct {
	Host            string        `yaml:"host"`
	Port            int           `yaml:"port"`
	User            string        `yaml:"user"`
	Password        string        `yaml:"password"`
	Database        string        `yaml:"database"`
	MaxIdleConns    int           `yaml:"max_idle_conns"`
	MaxOpenConns    int           `yaml:"max_open_conns"`
	ConnMaxLifetime time.Duration `yaml:"conn_max_lifetime"`
}
type MongoDBConfig struct {
	URI         string `yaml:"uri"`
	Database    string `yaml:"database"`
	MaxPoolSize uint64 `yaml:"max_pool_size"`
	MinPoolSize uint64 `yaml:"min_pool_size"`
}
type RedisConfig struct {
	// Addrs is the preferred field. Single host:port → standalone Redis; multiple
	// host:port values → Redis Cluster (go-redis UniversalClient picks the right
	// implementation based on len(Addrs)).
	Addrs []string `yaml:"addrs"`
	// Addr is kept for backwards compatibility with existing single-node
	// config files. When Addrs is empty and Addr is set, Addr is treated as
	// the single entry of Addrs.
	Addr         string `yaml:"addr"`
	Password     string `yaml:"password"`
	DB           int    `yaml:"db"`
	PoolSize     int    `yaml:"pool_size"`
	MinIdleConns int    `yaml:"min_idle_conns"`

	// ClusterOnly forces NewUniversalClient to build a ClusterClient even when
	// only a single address is supplied (useful when the address points at a
	// cluster-aware proxy such as an ElastiCache configuration endpoint).
	IsClusterMode bool `yaml:"is_cluster_mode"`
}

// ClusterConfig controls the multi-node API deployment features that are
// layered on top of the base Redis connection. When Enabled is false the
// server runs in single-node mode (no cross-node fan-out, no hash-tag
// enforcement); the same binary supports 1, 3, or N machines by toggling this
// flag plus the redis.addrs list.
type ClusterConfig struct {
	// Enabled gates cross-node WebSocket fan-out via Redis Pub/Sub. The
	// underlying Redis client (ClusterClient vs Client) is determined
	// independently by len(redis.addrs); this flag only controls whether
	// publishers and subscribers are wired up.
	Enabled bool `yaml:"enabled"`
	// NodeID is the stable identifier for this process (e.g. "node1"). It is
	// stamped onto every outbound cross-node event so other nodes can drop
	// their own echoed messages without doing extra work.
	NodeID string `yaml:"node_id"`
	// Channel is the Redis Pub/Sub channel used for cross-node WebSocket
	// fan-out. Defaults to "ws:node:fanout".
	Channel string `yaml:"channel"`
	// ShardedQueue splits the delayed/work queue into N hash-tagged shards so
	// each worker can BRPop from one shard while Cluster routes the key
	// deterministically. Leave false on single-node deployments.
	ShardedQueue bool `yaml:"sharded_queue"`
	// QueueShards is the number of shards used when ShardedQueue is true.
	// Ignored otherwise.
	QueueShards int `yaml:"queue_shards"`
}
type JWTConfig struct {
	Secret        string        `yaml:"secret"`
	Expire        time.Duration `yaml:"expire"`
	RefreshExpire time.Duration `yaml:"refresh_expire"`
}
type WebSocketConfig struct {
	ReadBufferSize  int           `yaml:"read_buffer_size"`
	WriteBufferSize int           `yaml:"write_buffer_size"`
	MaxMessageSize  int64         `yaml:"max_message_size"`
	PongWait        time.Duration `yaml:"pong_wait"`
	PingPeriod      time.Duration `yaml:"ping_period"`
	WriteWait       time.Duration `yaml:"write_wait"`
	AllowedOrigins  []string      `yaml:"allowed_origins"`
}
type ClientEndpointConfig struct {
	ID         string `yaml:"id" json:"id"`
	URL        string `yaml:"url" json:"url"`
	Priority   int    `yaml:"priority" json:"priority"`
	Region     string `yaml:"region,omitempty" json:"region,omitempty"`
	HealthPath string `yaml:"health_path,omitempty" json:"health_path,omitempty"`
}
type ClientBootstrapStrategyConfig struct {
	ConnectTimeoutMS  int  `yaml:"connect_timeout_ms" json:"connect_timeout_ms"`
	HealthTimeoutMS   int  `yaml:"health_timeout_ms" json:"health_timeout_ms"`
	FailThreshold     int  `yaml:"fail_threshold" json:"fail_threshold"`
	CooldownSeconds   int  `yaml:"cooldown_seconds" json:"cooldown_seconds"`
	PreferLastSuccess bool `yaml:"prefer_last_success" json:"prefer_last_success"`
}
type ClientBootstrapConfig struct {
	Enabled       bool                          `yaml:"enabled" json:"enabled"`
	Version       int                           `yaml:"version" json:"version"`
	TTLSeconds    int                           `yaml:"ttl_seconds" json:"ttl_seconds"`
	APIEndpoints  []ClientEndpointConfig        `yaml:"api_endpoints" json:"api_endpoints"`
	WSEndpoints   []ClientEndpointConfig        `yaml:"ws_endpoints" json:"ws_endpoints"`
	MediaBaseURLs []string                      `yaml:"media_base_urls" json:"media_base_urls"`
	Strategy      ClientBootstrapStrategyConfig `yaml:"strategy" json:"strategy"`
}
type MessageQueueConfig struct {
	ChannelBuffer int           `yaml:"channel_buffer"`
	Workers       int           `yaml:"workers"`
	BatchSize     int           `yaml:"batch_size"`
	FlushInterval time.Duration `yaml:"flush_interval"`
}

// MessageStorageConfig defines the user-visible message recovery boundary. // Idempotency records must never expire before the messages they protect.
type MessageStorageConfig struct {
	RetentionMonths   int `yaml:"retention_months"`
	IdempotencyMonths int `yaml:"idempotency_months"`
}
type ShardConfig struct {
	Count int `yaml:"count"`
}
type AgoraConfig struct {
	Enabled        bool   `yaml:"enabled"`
	AppID          string `yaml:"app_id"`
	AppCertificate string `yaml:"app_certificate"`
	TokenExpire    int    `yaml:"token_expire"`
}
type LiveKitConfig struct {
	Enabled     bool   `yaml:"enabled"`
	ServerURL   string `yaml:"server_url"`
	APIKey      string `yaml:"api_key"`
	APISecret   string `yaml:"api_secret"`
	TokenExpire int    `yaml:"token_expire"`
}

// StorageConfig controls where uploaded media is stored. // provider: local | aliyun | qiniu | s3. The database system setting overrides yaml.
type StorageConfig struct {
	Provider string `json:"provider" yaml:"provider"`
	Local    struct {
		BaseURL string `json:"base_url" yaml:"base_url"`
	} `json:"local" yaml:"local"`
	Aliyun struct {
		Endpoint string `json:"endpoint" yaml:"endpoint"`

		Bucket string `json:"bucket" yaml:"bucket"`

		AccessKeyID string `json:"access_key_id" yaml:"access_key_id"`

		AccessKeySecret string `json:"access_key_secret" yaml:"access_key_secret"`

		PublicBaseURL string `json:"public_base_url" yaml:"public_base_url"`

		UseHTTPS bool `json:"use_https" yaml:"use_https"`
	} `json:"aliyun" yaml:"aliyun"`
	Qiniu struct {
		UploadURL string `json:"upload_url" yaml:"upload_url"`

		Bucket string `json:"bucket" yaml:"bucket"`

		AccessKey string `json:"access_key" yaml:"access_key"`

		SecretKey string `json:"secret_key" yaml:"secret_key"`

		PublicBaseURL string `json:"public_base_url" yaml:"public_base_url"`

		UseHTTPS bool `json:"use_https" yaml:"use_https"`
	} `json:"qiniu" yaml:"qiniu"`
	S3 struct {
		Region string `json:"region" yaml:"region"`

		Bucket string `json:"bucket" yaml:"bucket"`

		AccessKeyID string `json:"access_key_id" yaml:"access_key_id"`

		SecretAccessKey string `json:"secret_access_key" yaml:"secret_access_key"`

		PublicBaseURL string `json:"public_base_url" yaml:"public_base_url"`

		Endpoint string `json:"endpoint" yaml:"endpoint"`

		UsePathStyle bool `json:"use_path_style" yaml:"use_path_style"`
	} `json:"s3" yaml:"s3"`
}

// PaymentConfig 微信/支付宝在线充值（notify_base_url 为公网可访问的根，如 https://api.example.com） // 管理后台可将密钥以 PEM 文本写入 private_key_pem / app_private_key_pem 等字段；与 yaml 文件配置二选一或互补。
type PaymentConfig struct {
	Enabled       bool    `json:"enabled" yaml:"enabled"`
	NotifyBaseURL string  `json:"notify_base_url" yaml:"notify_base_url"`
	MinAmount     float64 `json:"min_amount" yaml:"min_amount"`
	MaxAmount     float64 `json:"max_amount" yaml:"max_amount"`
	Wechat        struct {
		Enabled bool `json:"enabled" yaml:"enabled"`

		MchID string `json:"mch_id" yaml:"mch_id"`

		MchAPIv3Key string `json:"mch_api_v3_key" yaml:"mch_api_v3_key"`

		MchCertificateSerial string `json:"mch_certificate_serial" yaml:"mch_certificate_serial"`

		AppID string `json:"app_id" yaml:"app_id"`

		PrivateKeyPath string `json:"private_key_path,omitempty" yaml:"private_key_path"`

		PrivateKeyPEM string `json:"private_key_pem,omitempty" yaml:"private_key_pem,omitempty"`

		H5AppName string `json:"h5_app_name" yaml:"h5_app_name"`

		H5AppURL string `json:"h5_app_url" yaml:"h5_app_url"`

		H5BundleID string `json:"h5_bundle_id,omitempty" yaml:"h5_bundle_id"`

		H5PackageName string `json:"h5_package_name,omitempty" yaml:"h5_package_name"`
	} `json:"wechat" yaml:"wechat"`
	Alipay struct {
		Enabled bool `json:"enabled" yaml:"enabled"`

		AppID string `json:"app_id" yaml:"app_id"`

		PrivateKeyPath string `json:"private_key_path,omitempty" yaml:"private_key_path"`

		AppPrivateKeyPEM string `json:"app_private_key_pem,omitempty" yaml:"app_private_key_pem,omitempty"`

		AlipayPublicKeyPath string `json:"alipay_public_key_path,omitempty" yaml:"alipay_public_key_path"`

		AlipayPublicKeyPEM string `json:"alipay_public_key_pem,omitempty" yaml:"alipay_public_key_pem,omitempty"`

		IsProduction bool `json:"is_production" yaml:"is_production"`

		ReturnURL string `json:"return_url,omitempty" yaml:"return_url"`
	} `json:"alipay" yaml:"alipay"`
}

// SMSConfig 短信发送（绑定手机号验证码）；provider: smsbao | aliyun | tencent | console
type SMSConfig struct {
	Enabled         bool   `json:"enabled" yaml:"enabled"`
	Provider        string `json:"provider" yaml:"provider"`                 // smsbao | aliyun | tencent | console (debug only)
	MessageTemplate string `json:"message_template" yaml:"message_template"` // 仅短信宝：正文，需含占位符 {code}
	RuntimeOverride bool   `json:"-" yaml:"runtime_override"`                // 本地运行时忽略数据库网关配置
	SMSBao          struct {
		User string `json:"user" yaml:"user"`

		Password string `json:"password" yaml:"password"` // 登录密码，传输 MD5
	} `json:"smsbao" yaml:"smsbao"`
	Aliyun struct {
		AccessKeyID string `json:"access_key_id" yaml:"access_key_id"`

		AccessKeySecret string `json:"access_key_secret" yaml:"access_key_secret"`

		Region string `json:"region" yaml:"region"`

		SignName string `json:"sign_name" yaml:"sign_name"`

		TemplateCode string `json:"template_code" yaml:"template_code"`
	} `json:"aliyun" yaml:"aliyun"`
	Tencent struct {
		SecretID string `json:"secret_id" yaml:"secret_id"`

		SecretKey string `json:"secret_key" yaml:"secret_key"`

		Region string `json:"region" yaml:"region"`

		SdkAppID string `json:"sdk_app_id" yaml:"sdk_app_id"`

		SignName string `json:"sign_name" yaml:"sign_name"`

		TemplateID string `json:"template_id" yaml:"template_id"`
	} `json:"tencent" yaml:"tencent"`
}

// EmailConfig controls registration verification email delivery. // provider: smtp | console; console is available only in debug mode.
type EmailConfig struct {
	Enabled         bool   `json:"enabled" yaml:"enabled"`
	Provider        string `json:"provider" yaml:"provider"`
	RuntimeOverride bool   `json:"-" yaml:"runtime_override"`
	FromAddress     string `json:"from_address" yaml:"from_address"`
	FromName        string `json:"from_name" yaml:"from_name"`
	SubjectTemplate string `json:"subject_template" yaml:"subject_template"`
	BodyTemplate    string `json:"body_template" yaml:"body_template"`
	SMTP            struct {
		Host string `json:"host" yaml:"host"`

		Port int `json:"port" yaml:"port"`

		Username string `json:"username" yaml:"username"`

		Password string `json:"password" yaml:"password"`
	} `json:"smtp" yaml:"smtp"`
}

var GlobalConfig *Config

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {

		return nil, err
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {

		return nil, err
	}
	applyEnvOverrides(&cfg)
	if cfg.JWT.RefreshExpire <= 0 {

		cfg.JWT.RefreshExpire = 90 * 24 * time.Hour
	}
	if cfg.MessageStorage.RetentionMonths <= 0 {

		cfg.MessageStorage.RetentionMonths = 120
	}
	if cfg.MessageStorage.IdempotencyMonths < cfg.MessageStorage.RetentionMonths {

		cfg.MessageStorage.IdempotencyMonths = cfg.MessageStorage.RetentionMonths
	}
	if cfg.Cluster.Channel == "" {
		cfg.Cluster.Channel = "ws:node:fanout"
	}
	if cfg.Cluster.ShardedQueue && cfg.Cluster.QueueShards <= 0 {
		cfg.Cluster.QueueShards = 4
	}
	if cfg.Cluster.NodeID == "" {
		// Default to hostname-style identifier so logs and events are traceable
		// even when the operator forgets to set the variable.
		cfg.Cluster.NodeID = defaultNodeID()
	}
	GlobalConfig = &cfg
	return &cfg, nil
}

// defaultNodeID derives a stable fallback identifier for the current process.
// The hostname is good enough for human-readable log lines; deployments that
// care about distinguishing machines in a fixed order should override via the
// GENERIC_IM_CLUSTER_NODE_ID env var or the cluster.node_id config field.
func defaultNodeID() string {
	if h, err := os.Hostname(); err == nil && h != "" {
		return h
	}
	return "node-local"
}

// ValidateRuntime catches unsafe production defaults after all environment // overrides have been applied. Tests intentionally call Load without this gate // so bundled sample configs can stay lightweight.
func ValidateRuntime(cfg *Config) error {
	if cfg == nil {

		return fmt.Errorf("config is nil")
	}
	if strings.EqualFold(strings.TrimSpace(cfg.Server.Mode), "release") {

		if cfg.SMS.RuntimeOverride {

			return fmt.Errorf("sms.runtime_override must not be enabled in release mode")

		}

		if strings.EqualFold(strings.TrimSpace(cfg.SMS.Provider), "console") {

			return fmt.Errorf("sms.provider console is debug-only")

		}

		if cfg.Email.RuntimeOverride {

			return fmt.Errorf("email.runtime_override must not be enabled in release mode")

		}

		if strings.EqualFold(strings.TrimSpace(cfg.Email.Provider), "console") {

			return fmt.Errorf("email.provider console is debug-only")

		}

		if isWeakJWTSecret(cfg.JWT.Secret) {

			return fmt.Errorf("jwt.secret must be set to a strong non-sample value in release mode; use GENERIC_IM_JWT_SECRET or a private config file")

		}
		serverOrigins := trimStringList(cfg.Server.AllowedOrigins)

		if len(serverOrigins) == 0 {

			return fmt.Errorf("server.allowed_origins must be set in release mode")

		}

		if hasWildcardOrigin(serverOrigins) {

			return fmt.Errorf("server.allowed_origins must not contain * in release mode")

		}
		wsOrigins := trimStringList(cfg.WebSocket.AllowedOrigins)

		if len(wsOrigins) == 0 {

			return fmt.Errorf("websocket.allowed_origins must be set in release mode")

		}

		if hasWildcardOrigin(wsOrigins) {

			return fmt.Errorf("websocket.allowed_origins must not contain * in release mode")

		}
	}
	return nil
}
func applyEnvOverrides(cfg *Config) {
	// Honour the legacy single-node `redis.addr` field by promoting it to the
	// `redis.addrs` list when the operator hasn't supplied the new style.
	if len(cfg.Redis.Addrs) == 0 && strings.TrimSpace(cfg.Redis.Addr) != "" {
		cfg.Redis.Addrs = []string{strings.TrimSpace(cfg.Redis.Addr)}
	}
	cfg.Redis.Addrs = trimStringList(cfg.Redis.Addrs)
	setString("GENERIC_IM_SERVER_MODE", &cfg.Server.Mode)
	setInt("GENERIC_IM_SERVER_PORT", &cfg.Server.Port)
	setString("GENERIC_IM_SERVER_BASE_URL", &cfg.Server.BaseURL)
	setString("GENERIC_IM_REGISTER_BASE_URL", &cfg.Server.RegisterBaseURL)
	setStringList("GENERIC_IM_ALLOWED_ORIGINS", &cfg.Server.AllowedOrigins)
	setStringList("GENERIC_IM_WS_ALLOWED_ORIGINS", &cfg.WebSocket.AllowedOrigins)
	setBool("GENERIC_IM_CLIENT_BOOTSTRAP_ENABLED", &cfg.ClientBootstrap.Enabled)
	setInt("GENERIC_IM_CLIENT_BOOTSTRAP_VERSION", &cfg.ClientBootstrap.Version)
	setInt("GENERIC_IM_CLIENT_BOOTSTRAP_TTL_SECONDS", &cfg.ClientBootstrap.TTLSeconds)
	setEndpointList("GENERIC_IM_CLIENT_API_ENDPOINTS", &cfg.ClientBootstrap.APIEndpoints, "/api/v1/ping")
	setEndpointList("GENERIC_IM_CLIENT_WS_ENDPOINTS", &cfg.ClientBootstrap.WSEndpoints, "")
	setStringList("GENERIC_IM_CLIENT_MEDIA_BASE_URLS", &cfg.ClientBootstrap.MediaBaseURLs)
	setInt("GENERIC_IM_MESSAGE_RETENTION_MONTHS", &cfg.MessageStorage.RetentionMonths)
	setInt("GENERIC_IM_MESSAGE_IDEMPOTENCY_MONTHS", &cfg.MessageStorage.IdempotencyMonths)
	setString("GENERIC_IM_STORAGE_PROVIDER", &cfg.Storage.Provider)
	setString("GENERIC_IM_STORAGE_LOCAL_BASE_URL", &cfg.Storage.Local.BaseURL)
	setString("GENERIC_IM_STORAGE_ALIYUN_ENDPOINT", &cfg.Storage.Aliyun.Endpoint)
	setString("GENERIC_IM_STORAGE_ALIYUN_BUCKET", &cfg.Storage.Aliyun.Bucket)
	setString("GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_ID", &cfg.Storage.Aliyun.AccessKeyID)
	setString("GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_SECRET", &cfg.Storage.Aliyun.AccessKeySecret)
	setString("GENERIC_IM_STORAGE_ALIYUN_PUBLIC_BASE_URL", &cfg.Storage.Aliyun.PublicBaseURL)
	setBool("GENERIC_IM_STORAGE_ALIYUN_USE_HTTPS", &cfg.Storage.Aliyun.UseHTTPS)
	setString("GENERIC_IM_STORAGE_QINIU_UPLOAD_URL", &cfg.Storage.Qiniu.UploadURL)
	setString("GENERIC_IM_STORAGE_QINIU_BUCKET", &cfg.Storage.Qiniu.Bucket)
	setString("GENERIC_IM_STORAGE_QINIU_ACCESS_KEY", &cfg.Storage.Qiniu.AccessKey)
	setString("GENERIC_IM_STORAGE_QINIU_SECRET_KEY", &cfg.Storage.Qiniu.SecretKey)
	setString("GENERIC_IM_STORAGE_QINIU_PUBLIC_BASE_URL", &cfg.Storage.Qiniu.PublicBaseURL)
	setBool("GENERIC_IM_STORAGE_QINIU_USE_HTTPS", &cfg.Storage.Qiniu.UseHTTPS)
	setString("GENERIC_IM_MYSQL_HOST", &cfg.MySQL.Host)
	setInt("GENERIC_IM_MYSQL_PORT", &cfg.MySQL.Port)
	setString("GENERIC_IM_MYSQL_USER", &cfg.MySQL.User)
	setString("GENERIC_IM_MYSQL_PASSWORD", &cfg.MySQL.Password)
	setString("GENERIC_IM_MYSQL_DATABASE", &cfg.MySQL.Database)
	setString("GENERIC_IM_MONGODB_URI", &cfg.MongoDB.URI)
	setString("GENERIC_IM_MONGODB_DATABASE", &cfg.MongoDB.Database)
	setString("GENERIC_IM_REDIS_ADDR", &cfg.Redis.Addr)
	setStringList("GENERIC_IM_REDIS_CLUSTER_NODES", &cfg.Redis.Addrs)
	setString("GENERIC_IM_REDIS_PASSWORD", &cfg.Redis.Password)
	setInt("GENERIC_IM_REDIS_DB", &cfg.Redis.DB)
	setBool("GENERIC_IM_REDIS_IS_CLUSTER_MODE", &cfg.Redis.IsClusterMode)
	setBool("GENERIC_IM_CLUSTER_ENABLED", &cfg.Cluster.Enabled)
	setString("GENERIC_IM_CLUSTER_NODE_ID", &cfg.Cluster.NodeID)
	setString("GENERIC_IM_CLUSTER_CHANNEL", &cfg.Cluster.Channel)
	setBool("GENERIC_IM_CLUSTER_SHARDED_QUEUE", &cfg.Cluster.ShardedQueue)
	setInt("GENERIC_IM_CLUSTER_QUEUE_SHARDS", &cfg.Cluster.QueueShards)
	setString("GENERIC_IM_JWT_SECRET", &cfg.JWT.Secret)
	setDuration("GENERIC_IM_JWT_EXPIRE", &cfg.JWT.Expire)
	setDuration("GENERIC_IM_JWT_REFRESH_EXPIRE", &cfg.JWT.RefreshExpire)
	setBool("GENERIC_IM_AGORA_ENABLED", &cfg.Agora.Enabled)
	setString("GENERIC_IM_AGORA_APP_ID", &cfg.Agora.AppID)
	setString("GENERIC_IM_AGORA_APP_CERTIFICATE", &cfg.Agora.AppCertificate)
	setInt("GENERIC_IM_AGORA_TOKEN_EXPIRE", &cfg.Agora.TokenExpire)
	setBool("GENERIC_IM_LIVEKIT_ENABLED", &cfg.LiveKit.Enabled)
	setString("GENERIC_IM_LIVEKIT_SERVER_URL", &cfg.LiveKit.ServerURL)
	setString("GENERIC_IM_LIVEKIT_API_KEY", &cfg.LiveKit.APIKey)
	setString("GENERIC_IM_LIVEKIT_API_SECRET", &cfg.LiveKit.APISecret)
	setInt("GENERIC_IM_LIVEKIT_TOKEN_EXPIRE", &cfg.LiveKit.TokenExpire)
}
func setString(key string, target *string) {
	if value, ok := lookupTrimmedEnv(key); ok {

		*target = value
	}
}
func setStringList(key string, target *[]string) {
	if value, ok := lookupTrimmedEnv(key); ok {

		*target = trimStringList(strings.Split(value, ","))
	}
}
func setEndpointList(key string, target *[]ClientEndpointConfig, defaultHealthPath string) {
	value, ok := lookupTrimmedEnv(key)
	if !ok {

		return
	}
	values := trimStringList(strings.Split(value, ","))
	out := make([]ClientEndpointConfig, 0, len(values))
	for i, endpoint := range values {

		out = append(out, ClientEndpointConfig{

			ID: fmt.Sprintf("%s-%d", strings.ToLower(key), i+1),

			URL: strings.TrimRight(endpoint, "/"),

			Priority: (i + 1) * 10,

			HealthPath: defaultHealthPath,
		})
	}
	*target = out
}
func setInt(key string, target *int) {
	if value, ok := lookupTrimmedEnv(key); ok {

		parsed, err := strconv.Atoi(value)

		if err == nil {

			*target = parsed

		}
	}
}
func setBool(key string, target *bool) {
	if value, ok := lookupTrimmedEnv(key); ok {

		parsed, err := strconv.ParseBool(value)

		if err == nil {

			*target = parsed

		}
	}
}
func setDuration(key string, target *time.Duration) {
	if value, ok := lookupTrimmedEnv(key); ok {

		parsed, err := time.ParseDuration(value)

		if err == nil {

			*target = parsed

		}
	}
}
func lookupTrimmedEnv(key string) (string, bool) {
	value, ok := os.LookupEnv(key)
	if !ok {

		return "", false
	}
	return strings.TrimSpace(value), true
}
func trimStringList(values []string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {

		value = strings.TrimSpace(value)

		if value != "" {

			out = append(out, value)

		}
	}
	return out
}
func hasWildcardOrigin(values []string) bool {
	for _, value := range values {

		if strings.TrimSpace(value) == "*" {

			return true

		}
	}
	return false
}
func isWeakJWTSecret(secret string) bool {
	secret = strings.TrimSpace(secret)
	if len(secret) < 32 {

		return true
	}
	lower := strings.ToLower(secret)
	return strings.Contains(lower, "change-in-production") ||

		strings.Contains(lower, "your-super-secret") ||

		strings.Contains(lower, "example") ||

		strings.Contains(lower, "placeholder")
}
