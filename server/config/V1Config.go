package config

import (
	"os"
	"strconv"
	"strings"
	"time"
)

/*
	多端客户端 v1 API 相关配置
*/

const (
	// V1AccessTokenTTL access token 有效期
	V1AccessTokenTTL = 2 * time.Hour
	// V1RefreshTokenTTL refresh token 及设备会话有效期
	V1RefreshTokenTTL = 30 * 24 * time.Hour
	// V1SessionTouchInterval 会话活跃时间的刷新间隔, 避免每个请求都写 redis
	V1SessionTouchInterval = 10 * time.Minute

	// V1SessionKey 单台设备的会话信息 key: v1:session:{userId}:{deviceId}
	V1SessionKey = "v1:session:%d:%s"
	// V1UserSessionsKey 用户设备集合 key: v1:user:sessions:{userId}
	V1UserSessionsKey = "v1:user:sessions:%d"
	// V1SyncVersionKey 用户同步版本号 key: v1:sync:version:{userId}
	V1SyncVersionKey = "v1:sync:version:%d"

	V1TokenTypeAccess  = "access"
	V1TokenTypeRefresh = "refresh"
	V1TokenAudience    = "GoFilmV1"

	RoleAdmin = "admin"
	RoleUser  = "user"

	V1DefaultPageSize = 20
	V1MaxPageSize     = 60
	V1SyncBatchLimit  = 200

	// V1QRKey 扫码登录票据 key: v1:qr:{qid}
	V1QRKey = "v1:qr:%s"
	// V1QRTTL 二维码有效期
	V1QRTTL = 3 * time.Minute
	// V1QRPollInterval 客户端轮询间隔(秒)
	V1QRPollInterval = 2
	// V1QRCreateLimit 单 IP 每分钟创建票据上限
	V1QRCreateLimit  = 20
	V1QRCreateWindow = time.Minute

	V1QRStatusPending   = "pending"
	V1QRStatusScanned   = "scanned"
	V1QRStatusConfirmed = "confirmed"
	V1QRStatusExpired   = "expired"
	V1QRStatusCanceled  = "canceled"

	// V1ProxyURLTTL 媒体代理签名有效期
	V1ProxyURLTTL = 2 * time.Hour
	// V1ProxyTimeout 上游请求超时
	V1ProxyTimeout = 15 * time.Second
	// V1ProxyMaxPlaylist m3u8 文件大小上限
	V1ProxyMaxPlaylist = 4 << 20
	// V1ProxyMaxImage 图片大小上限
	V1ProxyMaxImage = 10 << 20
	// V1ProxyMaxResource 切片/密钥等资源大小上限
	V1ProxyMaxResource = 128 << 20
)

const (
	V1ClaimsContextKey  = "V1Claims"
	V1SessionContextKey = "V1Session"
)

// v1 响应业务码
const (
	V1CodeOK              = 0
	V1CodeBadRequest      = 40000
	V1CodeUnauthorized    = 40100
	V1CodeTokenExpired    = 40101
	V1CodeSessionInvalid  = 40102
	V1CodeForbidden       = 40300
	V1CodeNotFound        = 40400
	V1CodeConflict        = 40900
	V1CodeTooManyRequests = 42900
	V1CodeInternal        = 50000
)

/*
可通过环境变量覆盖的运行时配置
GOFILM_PUBLIC_BASE_URL  对外访问地址, 用于生成二维码链接, 例如 http://192.168.1.10:3601
GOFILM_PROXY_ENABLED    是否启用媒体代理, 默认 true
GOFILM_PROXY_SECRET     媒体代理签名密钥, 未设置时由 JWT 密钥派生
GOFILM_PROXY_ALLOWED_HOSTS 代理上游域名白名单, 逗号分隔, 支持 *.example.com 或 *
*/
var (
	V1PublicBaseURL = strings.TrimRight(env("GOFILM_PUBLIC_BASE_URL", ""), "/")

	V1ProxyEnabled      = envBool("GOFILM_PROXY_ENABLED", true)
	V1ProxySecret       = env("GOFILM_PROXY_SECRET", "")
	V1ProxyAllowedHosts = splitEnvList(env("GOFILM_PROXY_ALLOWED_HOSTS", ""))
)

func envBool(key string, def bool) bool {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return def
	}
	return b
}

func splitEnvList(v string) []string {
	if strings.TrimSpace(v) == "" {
		return nil
	}
	parts := strings.Split(v, ",")
	res := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(strings.ToLower(p)); p != "" {
			res = append(res, p)
		}
	}
	return res
}
