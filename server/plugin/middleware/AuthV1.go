package middleware

import (
	"errors"
	"net/http"
	"server/config"
	"server/model/system"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// AuthV1 多端客户端 Bearer token 校验
func AuthV1() gin.HandlerFunc {
	return func(c *gin.Context) {
		raw := bearerToken(c)
		if raw == "" {
			v1Abort(c, http.StatusUnauthorized, config.V1CodeUnauthorized, "请先登录")
			return
		}
		claims, err := system.ParseV1Token(raw)
		if err != nil {
			if errors.Is(err, jwt.ErrTokenExpired) {
				v1Abort(c, http.StatusUnauthorized, config.V1CodeTokenExpired, "登录状态已过期")
				return
			}
			v1Abort(c, http.StatusUnauthorized, config.V1CodeUnauthorized, "身份信息无效")
			return
		}
		if claims.TokenType != config.V1TokenTypeAccess {
			v1Abort(c, http.StatusUnauthorized, config.V1CodeUnauthorized, "token 类型错误")
			return
		}
		if claims.UserID == 0 || claims.DeviceID == "" || claims.SessionID == "" {
			v1Abort(c, http.StatusUnauthorized, config.V1CodeUnauthorized, "token 信息不完整")
			return
		}
		session, err := system.GetDeviceSession(claims.UserID, claims.DeviceID)
		if err != nil {
			v1Abort(c, http.StatusInternalServerError, config.V1CodeInternal, "会话信息读取失败")
			return
		}
		if session == nil || session.SessionID != claims.SessionID {
			v1Abort(c, http.StatusUnauthorized, config.V1CodeSessionInvalid, "登录状态已失效, 请重新登录")
			return
		}
		// 降低 redis 写入频率, 每 10 分钟刷新一次活跃时间
		if time.Since(time.UnixMilli(session.LastActiveAt)) > config.V1SessionTouchInterval {
			if err := system.TouchDeviceSession(session, c.ClientIP()); err != nil {
				// 活跃时间更新失败不影响本次请求
			}
		}
		c.Set(config.V1ClaimsContextKey, claims)
		c.Set(config.V1SessionContextKey, session)
		c.Next()
	}
}

func bearerToken(c *gin.Context) string {
	header := strings.TrimSpace(c.GetHeader("Authorization"))
	if header == "" {
		return ""
	}
	parts := strings.Fields(header)
	if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
		return parts[1]
	}
	return ""
}

func v1Abort(c *gin.Context, status, code int, msg string) {
	c.AbortWithStatusJSON(status, gin.H{
		"code": code,
		"data": nil,
		"msg":  msg,
	})
}
