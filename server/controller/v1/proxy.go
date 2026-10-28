package v1

import (
	"errors"
	"io"
	"log"
	"net/http"
	"net/url"
	"server/config"
	"server/plugin/mediaproxy"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// ProxyM3U8 m3u8 代理, 自动改写内部资源为签名地址
func ProxyM3U8(c *gin.Context) {
	raw, valid := parseProxyParams(c, mediaproxy.KindPlaylist)
	if !valid {
		return
	}
	data, _, _, err := mediaproxy.Default.FetchBytes(c.Request.Context(), raw, config.V1ProxyMaxPlaylist)
	if err != nil {
		proxyError(c, err)
		return
	}
	if !isM3U8(data) {
		fail(c, http.StatusBadGateway, config.V1CodeInternal, "上游返回的内容不是 m3u8")
		return
	}
	playlistURL, err := url.Parse(raw)
	if err != nil {
		fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "资源地址不合法")
		return
	}
	body := mediaproxy.RewritePlaylist(data, playlistURL, requestBaseURL(c))
	c.Header("Content-Type", "application/vnd.apple.mpegurl; charset=utf-8")
	c.Header("Cache-Control", "no-cache")
	c.Header("X-Content-Type-Options", "nosniff")
	setProxyCORS(c)
	c.Status(http.StatusOK)
	_, _ = c.Writer.Write(body)
}

// ProxyImage 图片代理
func ProxyImage(c *gin.Context) {
	raw, valid := parseProxyParams(c, mediaproxy.KindImage)
	if !valid {
		return
	}
	data, upstreamType, _, err := mediaproxy.Default.FetchBytes(c.Request.Context(), raw, config.V1ProxyMaxImage)
	if err != nil {
		proxyError(c, err)
		return
	}
	contentType := normalizeContentType(upstreamType)
	if !strings.HasPrefix(contentType, "image/") {
		contentType = http.DetectContentType(data)
	}
	if !strings.HasPrefix(contentType, "image/") {
		fail(c, http.StatusBadGateway, config.V1CodeInternal, "上游返回的内容不是图片")
		return
	}
	c.Header("Content-Type", contentType)
	c.Header("Content-Length", strconv.Itoa(len(data)))
	c.Header("Cache-Control", "public, max-age=86400")
	c.Header("X-Content-Type-Options", "nosniff")
	setProxyCORS(c)
	c.Status(http.StatusOK)
	_, _ = c.Writer.Write(data)
}

// ProxyResource 切片、密钥等二进制资源代理
func ProxyResource(c *gin.Context) {
	raw, valid := parseProxyParams(c, mediaproxy.KindResource)
	if !valid {
		return
	}
	resp, err := mediaproxy.Default.Fetch(c.Request.Context(), raw, c.GetHeader("Range"))
	if err != nil {
		proxyError(c, err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode >= http.StatusBadRequest {
		fail(c, http.StatusBadGateway, config.V1CodeInternal, "上游资源请求失败")
		return
	}
	if resp.ContentLength > config.V1ProxyMaxResource {
		fail(c, http.StatusRequestEntityTooLarge, config.V1CodeBadRequest, "上游资源超过大小限制")
		return
	}
	contentType := normalizeContentType(resp.Header.Get("Content-Type"))
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	c.Header("Content-Type", contentType)
	if resp.ContentLength >= 0 {
		c.Header("Content-Length", strconv.FormatInt(resp.ContentLength, 10))
	}
	if v := resp.Header.Get("Content-Range"); v != "" {
		c.Header("Content-Range", v)
	}
	if v := resp.Header.Get("Accept-Ranges"); v != "" {
		c.Header("Accept-Ranges", v)
	}
	c.Header("Cache-Control", "public, max-age=3600")
	c.Header("X-Content-Type-Options", "nosniff")
	setProxyCORS(c)
	c.Status(resp.StatusCode)
	n, err := io.Copy(c.Writer, io.LimitReader(resp.Body, config.V1ProxyMaxResource+1))
	if err != nil {
		log.Println("Proxy Resource Copy Error: ", err)
		return
	}
	if n > config.V1ProxyMaxResource {
		log.Println("Proxy Resource Exceeded Limit: ", raw)
	}
}

func parseProxyParams(c *gin.Context, kind string) (string, bool) {
	raw := strings.TrimSpace(c.Query("url"))
	exp, err := strconv.ParseInt(c.Query("exp"), 10, 64)
	if err != nil {
		fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "资源链接参数不合法")
		return "", false
	}
	if err := mediaproxy.Verify(kind, raw, exp, c.Query("sign")); err != nil {
		proxyError(c, err)
		return "", false
	}
	return raw, true
}

func proxyError(c *gin.Context, err error) {
	var pe *mediaproxy.Error
	if errors.As(err, &pe) {
		code := config.V1CodeInternal
		switch pe.Status {
		case http.StatusBadRequest, http.StatusRequestEntityTooLarge:
			code = config.V1CodeBadRequest
		case http.StatusForbidden:
			code = config.V1CodeForbidden
		case http.StatusTooManyRequests:
			code = config.V1CodeTooManyRequests
		}
		fail(c, pe.Status, code, pe.Msg)
		return
	}
	log.Println("Proxy Error: ", err)
	fail(c, http.StatusBadGateway, config.V1CodeInternal, "代理请求失败")
}

func setProxyCORS(c *gin.Context) {
	c.Header("Access-Control-Allow-Origin", "*")
	c.Header("Cross-Origin-Resource-Policy", "cross-origin")
}

func isM3U8(data []byte) bool {
	text := strings.TrimSpace(strings.TrimPrefix(string(data), "\ufeff"))
	return strings.HasPrefix(text, "#EXTM3U")
}

func normalizeContentType(v string) string {
	v = strings.TrimSpace(strings.ToLower(v))
	if i := strings.Index(v, ";"); i >= 0 {
		v = strings.TrimSpace(v[:i])
	}
	return v
}
