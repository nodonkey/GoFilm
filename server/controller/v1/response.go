package v1

import (
	"bytes"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"server/config"
	"server/logic"
	"server/model/system"
	"server/plugin/mediaproxy"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

type envelope struct {
	Code int    `json:"code"`
	Data any    `json:"data"`
	Msg  string `json:"msg"`
}

type pageMeta struct {
	PageSize  int  `json:"pageSize"`
	Current   int  `json:"current"`
	PageCount int  `json:"pageCount"`
	Total     int  `json:"total"`
	HasMore   bool `json:"hasMore"`
}

func ok(c *gin.Context, data any) {
	c.JSON(http.StatusOK, envelope{Code: config.V1CodeOK, Data: proxyImageURLs(data, requestBaseURL(c)), Msg: "ok"})
}

func okMsg(c *gin.Context, msg string) {
	c.JSON(http.StatusOK, envelope{Code: config.V1CodeOK, Data: nil, Msg: msg})
}

func created(c *gin.Context, data any) {
	c.JSON(http.StatusCreated, envelope{Code: config.V1CodeOK, Data: proxyImageURLs(data, requestBaseURL(c)), Msg: "ok"})
}

// imageJSONKeys 需要替换为图片代理地址的字段名
var imageJSONKeys = map[string]struct{}{
	"picture": {},
	"poster":  {},
	"cover":   {},
}

// proxyImageURLs 将响应中的海报/封面地址替换为签名代理地址, 避免源站防盗链导致图片无法加载
func proxyImageURLs(data any, base string) any {
	if !config.V1ProxyEnabled || base == "" {
		return data
	}
	raw, err := json.Marshal(data)
	if err != nil {
		return data
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var body any
	if err := dec.Decode(&body); err != nil {
		return data
	}
	walkImageURLs(body, base)
	return body
}

func walkImageURLs(node any, base string) {
	switch v := node.(type) {
	case map[string]any:
		for key, val := range v {
			if s, ok := val.(string); ok {
				if _, hit := imageJSONKeys[strings.ToLower(key)]; hit {
					v[key] = mediaproxy.SignedURL(base, mediaproxy.KindImage, s)
					continue
				}
			}
			walkImageURLs(val, base)
		}
	case []any:
		for _, item := range v {
			walkImageURLs(item, base)
		}
	}
}

func fail(c *gin.Context, status, code int, msg string) {
	c.JSON(status, envelope{Code: code, Data: nil, Msg: msg})
}

func handleError(c *gin.Context, err error) {
	var apiErr *logic.ApiError
	if errors.As(err, &apiErr) {
		fail(c, apiErr.Status, apiErr.Code, apiErr.Msg)
		return
	}
	log.Println("V1 API Error: ", err)
	fail(c, http.StatusInternalServerError, config.V1CodeInternal, "服务内部错误")
}

func bindJSON(c *gin.Context, dst any) bool {
	if err := c.ShouldBindJSON(dst); err != nil {
		fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "请求参数格式错误")
		return false
	}
	return true
}

func parsePagination(c *gin.Context) (int, int) {
	current, err := strconv.Atoi(c.DefaultQuery("current", "1"))
	if err != nil || current < 1 {
		current = 1
	}
	pageSize, err := strconv.Atoi(c.DefaultQuery("pageSize", strconv.Itoa(config.V1DefaultPageSize)))
	if err != nil || pageSize < 1 {
		pageSize = config.V1DefaultPageSize
	}
	if pageSize > config.V1MaxPageSize {
		pageSize = config.V1MaxPageSize
	}
	return current, pageSize
}

func newPageMeta(page system.Page) pageMeta {
	return pageMeta{
		PageSize:  page.PageSize,
		Current:   page.Current,
		PageCount: page.PageCount,
		Total:     page.Total,
		HasMore:   page.PageSize > 0 && page.Current*page.PageSize < page.Total,
	}
}

func parsePathMid(c *gin.Context) (int64, bool) {
	mid, err := strconv.ParseInt(c.Param("mid"), 10, 64)
	if err != nil || mid <= 0 {
		fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "影片ID不合法")
		return 0, false
	}
	return mid, true
}

func currentClaims(c *gin.Context) *system.V1Claims {
	v, ok := c.Get(config.V1ClaimsContextKey)
	if !ok {
		return nil
	}
	claims, _ := v.(*system.V1Claims)
	return claims
}

func currentSession(c *gin.Context) *system.DeviceSession {
	v, ok := c.Get(config.V1SessionContextKey)
	if !ok {
		return nil
	}
	session, _ := v.(*system.DeviceSession)
	return session
}

func currentUserID(c *gin.Context) (uint, bool) {
	claims := currentClaims(c)
	if claims == nil || claims.UserID == 0 {
		fail(c, http.StatusUnauthorized, config.V1CodeUnauthorized, "请先登录")
		return 0, false
	}
	return claims.UserID, true
}

// Health 健康检查
func Health(c *gin.Context) {
	ok(c, gin.H{"status": "ok", "apiVersion": "v1"})
}
