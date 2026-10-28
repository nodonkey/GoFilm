package mediaproxy

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"net/url"
	"server/config"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	KindPlaylist = "m3u8"
	KindImage    = "image"
	KindResource = "resource"
)

// Error 代理错误, 携带应返回给客户端的 HTTP 状态
type Error struct {
	Status int
	Msg    string
}

func (e *Error) Error() string {
	return e.Msg
}

func newError(status int, msg string) *Error {
	return &Error{Status: status, Msg: msg}
}

func Enabled() bool {
	return config.V1ProxyEnabled
}

// ShouldProxy 仅代理 http/https 资源
func ShouldProxy(raw string) bool {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return false
	}
	return u.Scheme == "http" || u.Scheme == "https"
}

var (
	secretOnce sync.Once
	secret     []byte
)

func signingSecret() []byte {
	secretOnce.Do(func() {
		if config.V1ProxySecret != "" {
			secret = []byte(config.V1ProxySecret)
			return
		}
		// 未显式配置时由 JWT 密钥派生, 保证重启后已签发的链接仍然有效
		sum := sha256.Sum256([]byte(config.PrivateKey + "\x00" + config.PublicKey + "\x00gofilm-media-proxy"))
		secret = []byte(hex.EncodeToString(sum[:]))
	})
	return secret
}

// Sign 生成带有效期的资源签名
func Sign(kind, target string, exp int64) string {
	mac := hmac.New(sha256.New, signingSecret())
	mac.Write([]byte(kind))
	mac.Write([]byte{'\n'})
	mac.Write([]byte(target))
	mac.Write([]byte{'\n'})
	mac.Write([]byte(strconv.FormatInt(exp, 10)))
	return hex.EncodeToString(mac.Sum(nil))[:32]
}

// Verify 校验签名与有效期
func Verify(kind, target string, exp int64, sig string) error {
	if target == "" {
		return newError(400, "缺少资源地址")
	}
	if !ShouldProxy(target) {
		return newError(400, "资源地址不合法")
	}
	if exp <= 0 || time.Now().Unix() > exp {
		return newError(403, "资源链接已过期")
	}
	if len(sig) != 32 {
		return newError(403, "资源链接签名无效")
	}
	expected := Sign(kind, target, exp)
	if subtle.ConstantTimeCompare([]byte(expected), []byte(strings.ToLower(sig))) != 1 {
		return newError(403, "资源链接签名无效")
	}
	return nil
}

func proxyPath(kind string) string {
	switch kind {
	case KindPlaylist:
		return "m3u8"
	case KindImage:
		return "image"
	default:
		return "resource"
	}
}

// SignedURL 生成客户端可访问的绝对代理地址
func SignedURL(baseURL, kind, target string) string {
	target = strings.TrimSpace(target)
	if !Enabled() || target == "" || !ShouldProxy(target) {
		return target
	}
	exp := time.Now().Add(config.V1ProxyURLTTL).Unix()
	q := url.Values{}
	q.Set("url", target)
	q.Set("exp", strconv.FormatInt(exp, 10))
	q.Set("sign", Sign(kind, target, exp))
	return strings.TrimRight(baseURL, "/") + "/api/v1/proxy/" + proxyPath(kind) + "?" + q.Encode()
}
