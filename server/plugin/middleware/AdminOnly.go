package middleware

import (
	"log"
	"net/http"
	"server/config"
	"server/model/system"

	"github.com/gin-gonic/gin"
)

// AdminOnly 管理后台接口仅允许管理员访问
func AdminOnly() gin.HandlerFunc {
	return func(c *gin.Context) {
		v, ok := c.Get(config.AuthUserClaims)
		if !ok {
			system.CustomResult(http.StatusUnauthorized, system.FAILED, nil, "用户未授权,请先登录", c)
			c.Abort()
			return
		}
		claims, ok := v.(*system.UserClaims)
		if !ok {
			system.CustomResult(http.StatusUnauthorized, system.FAILED, nil, "身份信息异常,请重新登录", c)
			c.Abort()
			return
		}
		u, err := system.FindUserByID(claims.UserID)
		if err != nil {
			log.Println("AdminOnly FindUser Failed: ", err)
			system.CustomResult(http.StatusForbidden, system.FAILED, nil, "无管理员权限", c)
			c.Abort()
			return
		}
		if u.Role != config.RoleAdmin {
			system.CustomResult(http.StatusForbidden, system.FAILED, nil, "无管理员权限", c)
			c.Abort()
			return
		}
		c.Next()
	}
}
