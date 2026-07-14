package config

import (
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	S3           S3Config           `yaml:"s3"`
	Server       ServerConfig       `yaml:"server"`
	MySQL        MySQLConfig        `yaml:"mysql"`
	MongoDB      MongoDBConfig      `yaml:"mongodb"`
	Redis        RedisConfig        `yaml:"redis"`
	JWT          JWTConfig          `yaml:"jwt"`
	WebSocket    WebSocketConfig    `yaml:"websocket"`
	MessageQueue MessageQueueConfig `yaml:"message_queue"`
	Shard        ShardConfig        `yaml:"shard"`
	Agora        AgoraConfig        `yaml:"agora"`
	Payment      PaymentConfig      `yaml:"payment"`
	SMS          SMSConfig          `yaml:"sms"`
	// ========== 新增：集群配置 ==========
	// 对应 config.yaml 中的 cluster 字段
	// 单机部署时不配置此项，程序自动降级为单机模式
	Cluster       *ClusterConfig       `yaml:"cluster"`
	Elasticsearch *ElasticsearchConfig `yaml:"elasticsearch"`
	// ========== 新增结束 ==========
}

// ========== 新增：ClusterConfig 集群配置 ==========
type ClusterConfig struct {
	// Enabled 是否启用集群模式
	// 也可通过环境变量 CLUSTER_ENABLED=true 覆盖
	Enabled bool `yaml:"enabled"`

	// NodeID 当前节点唯一标识，留空则自动读取环境变量 NODE_ID 或 hostname
	// 集群内每个节点必须唯一，建议命名规范：gateway-1 / gateway-2 / ...
	NodeID string `yaml:"node_id"`
}

// ========== 新增结束 ==========

type ServerConfig struct {
	Port                        int           `yaml:"port"`
	Mode                        string        `yaml:"mode"`
	ReadTimeout                 time.Duration `yaml:"read_timeout"`
	WriteTimeout                time.Duration `yaml:"write_timeout"`
	BaseURL                     string        `yaml:"base_url"`
	RegisterBaseURL             string        `yaml:"register_base_url"`
	UploadDir                   string        `yaml:"upload_dir"`
	ExternalCleanupHTTPDelete   bool          `yaml:"external_cleanup_http_delete"`
	ExternalCleanupAllowedHosts []string      `yaml:"external_cleanup_allowed_hosts"`

	// TrustedProxies 传给 Gin engine.SetTrustedProxies() 的 CIDR / IP 列表。
	// 只有来自这些地址的连接，才允许其 X-Forwarded-For / X-Real-IP 头被信任并
	// 参与 ClientIP() 计算 —— 关键防御，防止外网直接伪造 header 绕过 IP 限流。
	// 未配置或为 nil 时走 nil（Gin 视为不信任任何代理，只用 RemoteAddr）。
	// 配置示例：["127.0.0.1", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
	// 前面挂了 Nginx / K8s Ingress / CDN 时，写代理机器的内网段。
	TrustedProxies []string `yaml:"trusted_proxies"`

	// AllowedOrigins CORS 白名单（完整 scheme + host）。
	// 只有列表内的 Origin 才会被回写到 Access-Control-Allow-Origin 里，
	// 空则允许任意 origin（仅供开发使用，生产环境务必配置）。
	// 配置示例：["https://m.example.com", "https://www.example.com"]
	AllowedOrigins []string `yaml:"allowed_origins"`
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
	ConnMaxIdleTime time.Duration `yaml:"conn_max_idle_time"` // ★ 空闲连接超时释放
	ReplicaDSN      string        `yaml:"replica_dsn"`        // ★ 从库DSN，配置后启用读写分离
}

// S3Config AWS S3 存储配置
type S3Config struct {
	Enabled         bool   `yaml:"enabled"` // false 时退回本地存储
	Region          string `yaml:"region"`
	Bucket          string `yaml:"bucket"`
	AccessKeyID     string `yaml:"access_key_id"`
	SecretAccessKey string `yaml:"secret_access_key"`
	CDNBaseURL      string `yaml:"cdn_base_url"` // CloudFront 域名，可选
	Endpoint        string `yaml:"endpoint"`     // 兼容 MinIO，可选
}

type MongoDBConfig struct {
	URI         string `yaml:"uri"`
	Database    string `yaml:"database"`
	MaxPoolSize uint64 `yaml:"max_pool_size"`
	MinPoolSize uint64 `yaml:"min_pool_size"`
}

type RedisConfig struct {
	// 单机模式
	Addr string `yaml:"addr"`

	// Sentinel 模式（Mode=sentinel 时生效）
	Mode          string   `yaml:"mode"`           // "single"（默认）或 "sentinel"
	MasterName    string   `yaml:"master_name"`    // Sentinel 主节点名，默认 mymaster
	SentinelAddrs []string `yaml:"sentinel_addrs"` // Sentinel 节点列表

	// 通用
	Password     string `yaml:"password"`
	DB           int    `yaml:"db"`
	PoolSize     int    `yaml:"pool_size"`
	MinIdleConns int    `yaml:"min_idle_conns"`
}

type JWTConfig struct {
	// Secret 用户端 token 签名密钥（HS256），建议 openssl rand -hex 64 生成 (128 字节)。
	Secret string `yaml:"secret"`
	// AdminSecret 管理员端 token 签名密钥。留空则回退到 Secret（兼容旧配置），
	// 但强烈建议单独设置：即使用户端 secret 泄露，也不会连带打穿后台。
	AdminSecret   string        `yaml:"admin_secret"`
	Expire        time.Duration `yaml:"expire"`
	RefreshExpire time.Duration `yaml:"refresh_expire"`
}

// AdminSigningSecret 返回管理员 token 实际使用的签名密钥。
// 优先 admin_secret，回退到 secret（保证旧配置不炸）。
func (j JWTConfig) AdminSigningSecret() string {
	if j.AdminSecret != "" {
		return j.AdminSecret
	}
	return j.Secret
}

type WebSocketConfig struct {
	ReadBufferSize  int           `yaml:"read_buffer_size"`
	WriteBufferSize int           `yaml:"write_buffer_size"`
	MaxMessageSize  int64         `yaml:"max_message_size"`
	PongWait        time.Duration `yaml:"pong_wait"`
	PingPeriod      time.Duration `yaml:"ping_period"`
	WriteWait       time.Duration `yaml:"write_wait"`
}

type MessageQueueConfig struct {
	ChannelBuffer int           `yaml:"channel_buffer"`
	Workers       int           `yaml:"workers"`
	BatchSize     int           `yaml:"batch_size"`
	FlushInterval time.Duration `yaml:"flush_interval"`
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

// PaymentConfig 微信/支付宝在线充值
type PaymentConfig struct {
	Enabled       bool    `json:"enabled" yaml:"enabled"`
	NotifyBaseURL string  `json:"notify_base_url" yaml:"notify_base_url"`
	MinAmount     float64 `json:"min_amount" yaml:"min_amount"`
	MaxAmount     float64 `json:"max_amount" yaml:"max_amount"`
	Wechat        struct {
		Enabled              bool   `json:"enabled" yaml:"enabled"`
		MchID                string `json:"mch_id" yaml:"mch_id"`
		MchAPIv3Key          string `json:"mch_api_v3_key" yaml:"mch_api_v3_key"`
		MchCertificateSerial string `json:"mch_certificate_serial" yaml:"mch_certificate_serial"`
		AppID                string `json:"app_id" yaml:"app_id"`
		PrivateKeyPath       string `json:"private_key_path,omitempty" yaml:"private_key_path"`
		PrivateKeyPEM        string `json:"private_key_pem,omitempty" yaml:"private_key_pem,omitempty"`
		H5AppName            string `json:"h5_app_name" yaml:"h5_app_name"`
		H5AppURL             string `json:"h5_app_url" yaml:"h5_app_url"`
		H5BundleID           string `json:"h5_bundle_id,omitempty" yaml:"h5_bundle_id"`
		H5PackageName        string `json:"h5_package_name,omitempty" yaml:"h5_package_name"`
	} `json:"wechat" yaml:"wechat"`
	Alipay struct {
		Enabled             bool   `json:"enabled" yaml:"enabled"`
		AppID               string `json:"app_id" yaml:"app_id"`
		PrivateKeyPath      string `json:"private_key_path,omitempty" yaml:"private_key_path"`
		AppPrivateKeyPEM    string `json:"app_private_key_pem,omitempty" yaml:"app_private_key_pem,omitempty"`
		AlipayPublicKeyPath string `json:"alipay_public_key_path,omitempty" yaml:"alipay_public_key_path"`
		AlipayPublicKeyPEM  string `json:"alipay_public_key_pem,omitempty" yaml:"alipay_public_key_pem,omitempty"`
		IsProduction        bool   `json:"is_production" yaml:"is_production"`
		ReturnURL           string `json:"return_url,omitempty" yaml:"return_url"`
	} `json:"alipay" yaml:"alipay"`
}

// SMSConfig 短信发送（绑定手机号验证码）
type SMSConfig struct {
	Enabled         bool   `json:"enabled" yaml:"enabled"`
	Provider        string `json:"provider" yaml:"provider"`
	MessageTemplate string `json:"message_template" yaml:"message_template"`
	SMSBao          struct {
		User     string `json:"user" yaml:"user"`
		Password string `json:"password" yaml:"password"`
	} `json:"smsbao" yaml:"smsbao"`
	Aliyun struct {
		AccessKeyID     string `json:"access_key_id" yaml:"access_key_id"`
		AccessKeySecret string `json:"access_key_secret" yaml:"access_key_secret"`
		Region          string `json:"region" yaml:"region"`
		SignName        string `json:"sign_name" yaml:"sign_name"`
		TemplateCode    string `json:"template_code" yaml:"template_code"`
	} `json:"aliyun" yaml:"aliyun"`
	Tencent struct {
		SecretID   string `json:"secret_id" yaml:"secret_id"`
		SecretKey  string `json:"secret_key" yaml:"secret_key"`
		Region     string `json:"region" yaml:"region"`
		SdkAppID   string `json:"sdk_app_id" yaml:"sdk_app_id"`
		SignName   string `json:"sign_name" yaml:"sign_name"`
		TemplateID string `json:"template_id" yaml:"template_id"`
	} `json:"tencent" yaml:"tencent"`
}

// ElasticsearchConfig ES搜索配置
// ES机器未部署时留空，搜索功能自动降级为MongoDB正则搜索
type ElasticsearchConfig struct {
	Addresses []string `yaml:"addresses"` // ES节点地址列表，如 ["http://172.31.x.x:9200"]
	Username  string   `yaml:"username"`  // 默认 elastic
	Password  string   `yaml:"password"`
	Index     string   `yaml:"index"` // 索引名，默认 yixin_messages
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
	if cfg.JWT.RefreshExpire <= 0 {
		cfg.JWT.RefreshExpire = 90 * 24 * time.Hour
	}

	GlobalConfig = &cfg
	return &cfg, nil
}
